use std::collections::HashMap;
use std::path::{Component, Path, PathBuf};

use ammonia::{Builder, UrlRelative};
use pulldown_cmark::{html, Options, Parser};
use regex::Regex;
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderOptions {
    #[serde(default = "default_true")]
    pub enable_gfm: bool,
    #[serde(default = "default_true")]
    pub enable_mermaid: bool,
    #[serde(default = "default_true")]
    pub enable_math: bool,
    #[serde(default)]
    pub base_dir: Option<PathBuf>,
    #[serde(default)]
    pub allowed_root_dir: Option<PathBuf>,
    #[serde(default = "default_theme")]
    pub theme: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderedDocument {
    pub html: String,
    pub toc: Vec<TocItem>,
    pub diagnostics: Vec<Diagnostic>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TocItem {
    pub level: u8,
    pub title: String,
    pub anchor: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Diagnostic {
    pub code: String,
    pub message: String,
    pub resource: Option<String>,
}

#[derive(Debug, Error)]
pub enum RenderError {
    #[error("markdown render failed: {0}")]
    RenderFailure(String),
}

fn default_true() -> bool {
    true
}

fn default_theme() -> String {
    "github-light".to_string()
}

impl Default for RenderOptions {
    fn default() -> Self {
        Self {
            enable_gfm: true,
            enable_mermaid: true,
            enable_math: true,
            base_dir: None,
            allowed_root_dir: None,
            theme: default_theme(),
        }
    }
}

pub fn render_markdown(input: &str, opts: &RenderOptions) -> Result<RenderedDocument, RenderError> {
    let mut markdown_options = Options::empty();
    if opts.enable_gfm {
        markdown_options.insert(Options::ENABLE_TABLES);
        markdown_options.insert(Options::ENABLE_TASKLISTS);
        markdown_options.insert(Options::ENABLE_STRIKETHROUGH);
        markdown_options.insert(Options::ENABLE_FOOTNOTES);
        markdown_options.insert(Options::ENABLE_SMART_PUNCTUATION);
    }

    let parser = Parser::new_ext(input, markdown_options);
    let mut html_content = String::new();
    html::push_html(&mut html_content, parser);

    if opts.enable_mermaid {
        html_content = rewrite_mermaid_blocks(&html_content);
    }

    let toc = collect_toc(input);

    let mut diagnostics = Vec::new();
    html_content = enforce_resource_policy(
        &html_content,
        opts.base_dir.as_deref(),
        opts.allowed_root_dir.as_deref(),
        &mut diagnostics,
    );
    html_content = sanitize_html(&html_content);
    html_content = inject_heading_ids(&html_content, &toc);

    Ok(RenderedDocument {
        html: html_content,
        toc,
        diagnostics,
    })
}

fn enforce_resource_policy(
    html: &str,
    base_dir: Option<&Path>,
    allowed_root_dir: Option<&Path>,
    diagnostics: &mut Vec<Diagnostic>,
) -> String {
    let link_regex = Regex::new(r#"(<a[^>]*\shref=")([^"]*)(")"#).expect("valid link regex");
    let image_regex = Regex::new(r#"(<img[^>]*\ssrc=")([^"]*)(")"#).expect("valid image regex");

    let with_links = link_regex
        .replace_all(html, |caps: &regex::Captures<'_>| {
            let url = caps.get(2).map(|m| m.as_str()).unwrap_or_default();
            if is_allowed_resource(url, base_dir, allowed_root_dir) {
                caps.get(0).map(|m| m.as_str()).unwrap_or_default().to_string()
            } else {
                diagnostics.push(Diagnostic {
                    code: "blocked_resource".to_string(),
                    message: "Link blocked by local-base policy".to_string(),
                    resource: Some(url.to_string()),
                });
                format!(
                    "{}#blocked-resource{}",
                    caps.get(1).map(|m| m.as_str()).unwrap_or_default(),
                    caps.get(3).map(|m| m.as_str()).unwrap_or_default()
                )
            }
        })
        .to_string();

    image_regex
        .replace_all(&with_links, |caps: &regex::Captures<'_>| {
            let url = caps.get(2).map(|m| m.as_str()).unwrap_or_default();
            if is_allowed_resource(url, base_dir, allowed_root_dir) {
                caps.get(0).map(|m| m.as_str()).unwrap_or_default().to_string()
            } else {
                diagnostics.push(Diagnostic {
                    code: "blocked_resource".to_string(),
                    message: "Image blocked by local-base policy".to_string(),
                    resource: Some(url.to_string()),
                });
                format!(
                    "{}{}",
                    caps.get(1).map(|m| m.as_str()).unwrap_or_default(),
                    caps.get(3).map(|m| m.as_str()).unwrap_or_default()
                )
            }
        })
        .to_string()
}

fn is_allowed_resource(url: &str, base_dir: Option<&Path>, allowed_root_dir: Option<&Path>) -> bool {
    if url.is_empty() || url.starts_with('#') {
        return true;
    }

    if url.starts_with("http://")
        || url.starts_with("https://")
        || url.starts_with("mailto:")
        || url.starts_with("tel:")
    {
        return true;
    }

    if url.starts_with("file://") {
        return false;
    }

    if url.contains(':') {
        return false;
    }

    if url.starts_with('/') {
        return false;
    }

    let Some(base_dir) = base_dir else {
        return false;
    };

    let raw_path = url.split(['?', '#']).next().unwrap_or_default();
    if raw_path.is_empty() {
        return true;
    }

    let candidate = Path::new(raw_path);
    if candidate.is_absolute() {
        return false;
    }

    let Some(joined) = normalize_path(&base_dir.join(candidate)) else {
        return false;
    };

    let boundary = allowed_root_dir.unwrap_or(base_dir);
    let Some(normalized_boundary) = canonical_or_normalized(boundary) else {
        return false;
    };

    let normalized_target = joined.canonicalize().ok().unwrap_or(joined);
    normalized_target.starts_with(normalized_boundary)
}

fn canonical_or_normalized(path: &Path) -> Option<PathBuf> {
    path.canonicalize().ok().or_else(|| normalize_path(path))
}

fn normalize_path(path: &Path) -> Option<PathBuf> {
    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Prefix(prefix) => normalized.push(prefix.as_os_str()),
            Component::RootDir => normalized.push(Path::new("/")),
            Component::CurDir => {}
            Component::Normal(value) => normalized.push(value),
            Component::ParentDir => {
                if !normalized.pop() {
                    return None;
                }
            }
        }
    }

    Some(normalized)
}

fn collect_toc(input: &str) -> Vec<TocItem> {
    let mut toc = Vec::new();
    let mut slug_counts = HashMap::<String, usize>::new();

    for line in input.lines() {
        let trimmed = line.trim();
        if !trimmed.starts_with('#') {
            continue;
        }

        let level = trimmed.chars().take_while(|ch| *ch == '#').count();
        if level == 0 || level > 6 {
            continue;
        }

        let title = trimmed[level..]
            .trim()
            .trim_end_matches('#')
            .trim()
            .to_string();
        if title.is_empty() {
            continue;
        }

        let base_slug = slugify(&title);
        let count = slug_counts.entry(base_slug.clone()).or_insert(0);
        let slug = if *count == 0 {
            base_slug
        } else {
            format!("{}-{}", base_slug, *count)
        };
        *count += 1;

        toc.push(TocItem {
            level: level as u8,
            title,
            anchor: format!("user-content-{slug}"),
        });
    }

    toc
}

fn slugify(value: &str) -> String {
    let mut slug = String::new();
    for ch in value.chars() {
        if ch.is_ascii_alphanumeric() {
            slug.push(ch.to_ascii_lowercase());
        } else if ch.is_whitespace() || ch == '-' {
            if !slug.ends_with('-') {
                slug.push('-');
            }
        }
    }

    slug.trim_matches('-').to_string()
}

fn sanitize_html(html: &str) -> String {
    let mut builder = Builder::default();
    builder.add_tags([
        "table", "thead", "tbody", "tr", "th", "td", "pre", "code", "div", "span", "input", "details",
        "summary", "sup", "sub", "kbd", "figure", "figcaption",
    ]);
    builder.add_generic_attributes(["class", "id", "role", "aria-hidden"]);
    builder.add_tag_attributes("a", ["href", "title"]);
    builder.add_tag_attributes("img", ["src", "alt", "title", "width", "height"]);
    builder.add_tag_attributes("input", ["type", "checked", "disabled"]);
    builder.add_tag_attributes("code", ["class"]);
    builder.add_tag_attributes("div", ["class"]);
    builder.add_tag_attributes("span", ["class"]);
    builder.url_schemes(["http", "https", "mailto", "tel"].into());
    builder.url_relative(UrlRelative::PassThrough);
    builder.clean(html).to_string()
}

fn inject_heading_ids(html: &str, toc: &[TocItem]) -> String {
    let regex = Regex::new(r"(?s)<h([1-6])>(.*?)</h[1-6]>").expect("valid heading regex");
    let mut index = 0usize;

    regex
        .replace_all(html, |caps: &regex::Captures<'_>| {
            let level = caps
                .get(1)
                .and_then(|v| v.as_str().parse::<u8>().ok())
                .unwrap_or(1);
            let contents = caps.get(2).map(|m| m.as_str()).unwrap_or_default();

            let anchor = toc
                .iter()
                .skip(index)
                .find(|item| item.level == level)
                .map(|item| item.anchor.clone())
                .unwrap_or_else(|| format!("user-content-heading-{index}"));
            index += 1;

            format!("<h{level} id=\"{anchor}\">{contents}</h{level}>")
        })
        .to_string()
}

fn rewrite_mermaid_blocks(html: &str) -> String {
    let regex = Regex::new(r#"(?s)<pre><code class="language-mermaid">(.*?)</code></pre>"#)
        .expect("valid mermaid regex");
    regex
        .replace_all(html, |caps: &regex::Captures<'_>| {
            let body = caps.get(1).map(|m| m.as_str()).unwrap_or_default();
            format!("<div class=\"mermaid\">{body}</div>")
        })
        .to_string()
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::{render_markdown, RenderOptions};

    #[test]
    fn renders_tables_and_task_lists() {
        let input = "| A | B |\n|---|---|\n| 1 | 2 |\n\n- [x] done\n- [ ] todo\n";
        let output = render_markdown(input, &RenderOptions::default()).expect("render should pass");

        assert!(output.html.contains("<table>"));
        assert!(output.html.contains("checkbox"));
    }

    #[test]
    fn blocks_non_local_relative_paths() {
        let input = "![x](../secret.png)\n[bad](/etc/passwd)\n[ok](same.md)\n[subdir](docs/file.md)";
        let options = RenderOptions {
            base_dir: Some(PathBuf::from("/tmp/base")),
            ..RenderOptions::default()
        };

        let output = render_markdown(input, &options).expect("render should pass");
        assert_eq!(output.diagnostics.len(), 2);
        assert!(output.html.contains("same.md"));
        assert!(output.html.contains("docs/file.md"));
    }

    #[test]
    fn allows_parent_links_within_allowed_root() {
        let input = "[ok](../background-knowledge/topic.md)\n[blocked](../../outside.md)";
        let options = RenderOptions {
            base_dir: Some(PathBuf::from("/tmp/repo/docs/standards")),
            allowed_root_dir: Some(PathBuf::from("/tmp/repo/docs")),
            ..RenderOptions::default()
        };

        let output = render_markdown(input, &options).expect("render should pass");
        assert_eq!(output.diagnostics.len(), 1);
        assert!(output.html.contains("../background-knowledge/topic.md"));
    }

    #[test]
    fn sanitizes_script_tags() {
        let input = "<script>alert('x')</script>\n\n# Header";
        let output = render_markdown(input, &RenderOptions::default()).expect("render should pass");

        assert!(!output.html.contains("<script>"));
        assert!(output.html.contains("id=\"user-content-header\""));
    }

    #[test]
    fn rewrites_mermaid_code_blocks() {
        let input = "```mermaid\nflowchart TD\nA-->B\n```";
        let output = render_markdown(input, &RenderOptions::default()).expect("render should pass");

        assert!(output.html.contains("<div class=\"mermaid\">"));
        assert!(output.html.contains("flowchart TD"));
    }

    #[test]
    fn keeps_math_text_visible_for_offline_typesetting() {
        let input = "Inline math $E=mc^2$ and block:\n\n$$a^2 + b^2 = c^2$$";
        let output = render_markdown(input, &RenderOptions::default()).expect("render should pass");

        assert!(output.html.contains("E=mc^2"));
        assert!(output.html.contains("a^2 + b^2 = c^2"));
    }

    #[test]
    fn preserves_relative_image_src_after_sanitization() {
        let input = "![Tool Lock-in Spectrum](analysis/data/figures/fig-lock-in-spectrum.png)";
        let options = RenderOptions {
            base_dir: Some(PathBuf::from("/tmp/repo")),
            allowed_root_dir: Some(PathBuf::from("/tmp/repo")),
            ..RenderOptions::default()
        };
        let output = render_markdown(input, &options).expect("render should pass");
        eprintln!("HTML output: {}", output.html);
        assert!(
            output.html.contains(r#"src="analysis/data/figures/fig-lock-in-spectrum.png""#),
            "Image src should be preserved. Got: {}",
            output.html
        );
        assert!(output.diagnostics.is_empty(), "No diagnostics expected");
    }

    #[test]
    fn generates_unique_toc_anchors() {
        let input = "# Same\n## Same\n";
        let output = render_markdown(input, &RenderOptions::default()).expect("render should pass");

        assert_eq!(output.toc.len(), 2);
        assert_eq!(output.toc[0].anchor, "user-content-same");
        assert_eq!(output.toc[1].anchor, "user-content-same-1");
    }
}
