use std::collections::HashMap;
use std::path::{Component, Path, PathBuf};

use ammonia::{Builder, UrlRelative};
use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine as _;
use percent_encoding::percent_decode_str;
use pulldown_cmark::{html, CowStr, Event, HeadingLevel, Options, Parser, Tag, TagEnd};
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
    #[serde(default)]
    pub embed_local_images: bool,
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
            embed_local_images: false,
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
    }

    if opts.enable_math {
        markdown_options.insert(Options::ENABLE_MATH);
    }

    let parser = Parser::new_ext(input, markdown_options);
    let (events, toc) = add_heading_ids_and_collect_toc(parser);
    let mut html_content = String::new();
    html::push_html(&mut html_content, events.into_iter());

    if opts.enable_mermaid {
        html_content = rewrite_mermaid_blocks(&html_content);
    }

    let mut diagnostics = Vec::new();
    if opts.embed_local_images {
        html_content =
            embed_preview_images(&html_content, opts.base_dir.as_deref(), &mut diagnostics);
    }
    html_content = enforce_resource_policy(
        &html_content,
        opts.base_dir.as_deref(),
        opts.allowed_root_dir.as_deref(),
        opts.embed_local_images,
        &mut diagnostics,
    );
    html_content = sanitize_html(&html_content, opts.embed_local_images);

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
    allow_embedded_images: bool,
    diagnostics: &mut Vec<Diagnostic>,
) -> String {
    let link_regex = Regex::new(r#"(<a[^>]*\shref=")([^"]*)(")"#).expect("valid link regex");
    let image_regex = Regex::new(r#"(<img[^>]*\ssrc=")([^"]*)(")"#).expect("valid image regex");

    let with_links = link_regex
        .replace_all(html, |caps: &regex::Captures<'_>| {
            let url = caps.get(2).map(|m| m.as_str()).unwrap_or_default();
            if is_allowed_resource(url, base_dir, allowed_root_dir) {
                if url.starts_with("http://") || url.starts_with("https://") {
                    diagnostics.push(Diagnostic {
                        code: "external_link".to_string(),
                        message: "Link to external source".to_string(),
                        resource: Some(url.to_string()),
                    });
                }
                caps.get(0)
                    .map(|m| m.as_str())
                    .unwrap_or_default()
                    .to_string()
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
            if (allow_embedded_images && is_safe_embedded_image(url))
                || is_allowed_resource(url, base_dir, allowed_root_dir)
            {
                if url.starts_with("http://") || url.starts_with("https://") {
                    diagnostics.push(Diagnostic {
                        code: "external_image".to_string(),
                        message: "Image loaded from external source".to_string(),
                        resource: Some(url.to_string()),
                    });
                }
                caps.get(0)
                    .map(|m| m.as_str())
                    .unwrap_or_default()
                    .to_string()
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

const MAX_PREVIEW_IMAGE_BYTES: u64 = 2 * 1024 * 1024;
const MAX_PREVIEW_IMAGES_BYTES: u64 = 10 * 1024 * 1024;

fn embed_preview_images(
    html: &str,
    base_dir: Option<&Path>,
    diagnostics: &mut Vec<Diagnostic>,
) -> String {
    let image_regex = Regex::new(r#"<img\s+src="([^"]*)"([^>]*)>"#).expect("valid image regex");
    let Some(base_dir) = base_dir else {
        return html.to_string();
    };
    let Some(canonical_base) = base_dir.canonicalize().ok() else {
        return html.to_string();
    };
    let mut total_bytes = 0u64;

    image_regex
        .replace_all(html, |caps: &regex::Captures<'_>| {
            let source = caps.get(1).map(|m| m.as_str()).unwrap_or_default();
            let attributes = caps.get(2).map(|m| m.as_str()).unwrap_or_default();
            if source.starts_with("http://") || source.starts_with("https://") {
                diagnostics.push(Diagnostic {
                    code: "external_image_blocked".to_string(),
                    message: "Remote image blocked in Quick Look preview".to_string(),
                    resource: Some(source.to_string()),
                });
                return format!(
                    "<span class=\"ql-remote-image\">Remote image blocked: {}</span>",
                    escape_html_text(source)
                );
            }

            let decoded = percent_decode_str(source).decode_utf8();
            let relative_path = match decoded {
                Ok(value) if !value.is_empty() && !value.contains(':') => value,
                _ => return preview_image_placeholder("Image path is not permitted", source),
            };
            let path_part = relative_path.split(['?', '#']).next().unwrap_or_default();
            let candidate = base_dir.join(path_part);
            let canonical_target = match candidate.canonicalize() {
                Ok(path) if path.starts_with(&canonical_base) => path,
                _ => {
                    diagnostics.push(blocked_preview_image(source));
                    return preview_image_placeholder(
                        "Image is outside the document folder",
                        source,
                    );
                }
            };
            let content_type = match canonical_target
                .extension()
                .and_then(|extension| extension.to_str())
                .map(|extension| extension.to_ascii_lowercase())
                .as_deref()
            {
                Some("png") => "image/png",
                Some("jpg" | "jpeg") => "image/jpeg",
                Some("gif") => "image/gif",
                Some("webp") => "image/webp",
                _ => {
                    diagnostics.push(blocked_preview_image(source));
                    return preview_image_placeholder(
                        "Image format is not supported in Quick Look",
                        source,
                    );
                }
            };
            let file = match std::fs::File::open(&canonical_target) {
                Ok(file) => file,
                Err(_) => {
                    diagnostics.push(blocked_preview_image(source));
                    return preview_image_placeholder("Image could not be read", source);
                }
            };
            let file_size = match file.metadata() {
                Ok(metadata) if metadata.is_file() => metadata.len(),
                _ => {
                    diagnostics.push(blocked_preview_image(source));
                    return preview_image_placeholder("Image could not be read", source);
                }
            };
            if file_size > MAX_PREVIEW_IMAGE_BYTES
                || total_bytes.saturating_add(file_size) > MAX_PREVIEW_IMAGES_BYTES
            {
                diagnostics.push(blocked_preview_image(source));
                return preview_image_placeholder("Image exceeds Quick Look size limit", source);
            }
            let bytes = match std::fs::read(&canonical_target) {
                Ok(bytes) if bytes.len() as u64 == file_size => bytes,
                _ => {
                    diagnostics.push(blocked_preview_image(source));
                    return preview_image_placeholder("Image could not be read", source);
                }
            };
            total_bytes += file_size;
            let encoded = BASE64.encode(bytes);
            format!("<img src=\"data:{content_type};base64,{encoded}\"{attributes}>")
        })
        .to_string()
}

fn blocked_preview_image(source: &str) -> Diagnostic {
    Diagnostic {
        code: "blocked_resource".to_string(),
        message: "Image blocked by Quick Look local image policy".to_string(),
        resource: Some(source.to_string()),
    }
}

fn preview_image_placeholder(message: &str, source: &str) -> String {
    format!(
        "<span class=\"ql-remote-image\">{}: {}</span>",
        escape_html_text(message),
        escape_html_text(source)
    )
}

fn escape_html_text(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

fn is_safe_embedded_image(url: &str) -> bool {
    let Some((metadata, encoded)) = url
        .strip_prefix("data:")
        .and_then(|value| value.split_once(','))
    else {
        return false;
    };
    let content_type = metadata.split(';').next().unwrap_or_default();
    matches!(
        content_type,
        "image/png" | "image/jpeg" | "image/gif" | "image/webp"
    ) && metadata.ends_with(";base64")
        && !encoded.is_empty()
}

fn is_allowed_resource(
    url: &str,
    base_dir: Option<&Path>,
    allowed_root_dir: Option<&Path>,
) -> bool {
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

fn add_heading_ids_and_collect_toc<'a>(parser: Parser<'a>) -> (Vec<Event<'a>>, Vec<TocItem>) {
    struct ActiveHeading<'a> {
        level: HeadingLevel,
        start: Event<'a>,
        contents: Vec<Event<'a>>,
    }

    let mut output = Vec::new();
    let mut toc = Vec::new();
    let mut slug_counts = HashMap::<String, usize>::new();
    let mut active_heading: Option<ActiveHeading<'a>> = None;

    for event in parser {
        if let Some(mut active) = active_heading.take() {
            if matches!(event, Event::End(TagEnd::Heading(level)) if level == active.level) {
                let title = heading_title(&active.contents);
                let anchor = unique_heading_anchor(&title, &mut slug_counts);
                let level_number = heading_level_number(active.level);
                toc.push(TocItem {
                    level: level_number,
                    title,
                    anchor: anchor.clone(),
                });
                let (classes, attrs) = match active.start {
                    Event::Start(Tag::Heading { classes, attrs, .. }) => (classes, attrs),
                    _ => unreachable!("active heading starts with heading event"),
                };
                output.push(Event::Start(Tag::Heading {
                    level: active.level,
                    id: Some(CowStr::from(anchor)),
                    classes,
                    attrs,
                }));
                output.extend(active.contents);
                output.push(event);
            } else {
                active.contents.push(event);
                active_heading = Some(active);
            }
            continue;
        }

        match event {
            Event::Start(Tag::Heading {
                level,
                id,
                classes,
                attrs,
            }) => {
                active_heading = Some(ActiveHeading {
                    level,
                    start: Event::Start(Tag::Heading {
                        level,
                        id,
                        classes,
                        attrs,
                    }),
                    contents: Vec::new(),
                });
            }
            other => output.push(other),
        }
    }

    (output, toc)
}

fn heading_title(events: &[Event<'_>]) -> String {
    let mut title = String::new();
    for event in events {
        match event {
            Event::Text(value)
            | Event::Code(value)
            | Event::InlineMath(value)
            | Event::DisplayMath(value) => title.push_str(value),
            Event::SoftBreak | Event::HardBreak => title.push(' '),
            _ => {}
        }
    }
    title.trim().to_string()
}

fn heading_level_number(level: HeadingLevel) -> u8 {
    match level {
        HeadingLevel::H1 => 1,
        HeadingLevel::H2 => 2,
        HeadingLevel::H3 => 3,
        HeadingLevel::H4 => 4,
        HeadingLevel::H5 => 5,
        HeadingLevel::H6 => 6,
    }
}

fn unique_heading_anchor(title: &str, slug_counts: &mut HashMap<String, usize>) -> String {
    let base_slug = slugify(title);
    let count = slug_counts.entry(base_slug.clone()).or_insert(0);
    let slug = if *count == 0 {
        base_slug
    } else {
        format!("{base_slug}-{count}")
    };
    *count += 1;
    format!("user-content-{slug}")
}

fn slugify(value: &str) -> String {
    let mut slug = String::new();
    for ch in value.chars() {
        if ch.is_alphanumeric() {
            for lower in ch.to_lowercase() {
                slug.push(lower);
            }
        } else if ch.is_whitespace() || ch == '-' {
            if !slug.ends_with('-') {
                slug.push('-');
            }
        }
    }

    slug.trim_matches('-').to_string()
}

fn sanitize_html(html: &str, allow_embedded_images: bool) -> String {
    let mut builder = Builder::default();
    builder.add_tags([
        "table",
        "thead",
        "tbody",
        "tr",
        "th",
        "td",
        "pre",
        "code",
        "div",
        "span",
        "input",
        "details",
        "summary",
        "sup",
        "sub",
        "kbd",
        "figure",
        "figcaption",
    ]);
    builder.add_generic_attributes(["class", "id", "role", "aria-hidden"]);
    builder.add_tag_attributes("a", ["href", "title"]);
    builder.add_tag_attributes("img", ["src", "alt", "title", "width", "height"]);
    builder.add_tag_attributes("input", ["type", "checked", "disabled"]);
    builder.add_tag_attributes("code", ["class"]);
    builder.add_tag_attributes("div", ["class"]);
    builder.add_tag_attributes("span", ["class"]);
    let schemes = if allow_embedded_images {
        ["http", "https", "mailto", "tel", "data"]
    } else {
        ["http", "https", "mailto", "tel", ""]
    };
    builder.url_schemes(
        schemes
            .into_iter()
            .filter(|scheme| !scheme.is_empty())
            .collect(),
    );
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
    use base64::Engine as _;
    use std::path::PathBuf;

    use super::{render_markdown, RenderOptions, BASE64, MAX_PREVIEW_IMAGE_BYTES};

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
            output
                .html
                .contains(r#"src="analysis/data/figures/fig-lock-in-spectrum.png""#),
            "Image src should be preserved. Got: {}",
            output.html
        );
        assert!(output.diagnostics.is_empty(), "No diagnostics expected");
    }

    #[test]
    fn preview_embeds_local_images_and_replaces_remote_images() {
        let directory = std::env::temp_dir().join(format!("md-engine-preview-{}", uuid_for_test()));
        std::fs::create_dir_all(&directory).expect("create fixture directory");
        let image = BASE64
            .decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j8ioAAAAASUVORK5CYII=")
            .expect("valid test png");
        std::fs::write(directory.join("pixel.png"), image).expect("write test image");
        let input = "![local](pixel.png)\n\n![remote](https://example.com/pixel.png)";
        let options = RenderOptions {
            base_dir: Some(directory.clone()),
            allowed_root_dir: Some(directory.clone()),
            embed_local_images: true,
            ..RenderOptions::default()
        };

        let output = render_markdown(input, &options).expect("render should pass");
        assert!(output.html.contains("src=\"data:image/png;base64,"));
        assert!(output
            .html
            .contains("Remote image blocked: https://example.com/pixel.png"));
        assert!(!output
            .html
            .contains("src=\"https://example.com/pixel.png\""));
        assert_eq!(output.diagnostics.len(), 1);

        std::fs::remove_dir_all(directory).expect("remove fixture directory");
    }

    #[test]
    fn preview_does_not_embed_images_outside_the_document_directory() {
        let parent =
            std::env::temp_dir().join(format!("md-engine-preview-root-{}", uuid_for_test()));
        let directory = parent.join("docs");
        std::fs::create_dir_all(&directory).expect("create fixture directory");
        std::fs::write(parent.join("outside.png"), b"not an image").expect("write outside file");
        let options = RenderOptions {
            base_dir: Some(directory.clone()),
            allowed_root_dir: Some(directory.clone()),
            embed_local_images: true,
            ..RenderOptions::default()
        };

        let output =
            render_markdown("![outside](../outside.png)", &options).expect("render should pass");
        assert!(!output.html.contains("src=\"data:"));
        assert!(output.html.contains("Image is outside the document folder"));
        assert_eq!(output.diagnostics.len(), 1);

        std::fs::remove_dir_all(parent).expect("remove fixture directory");
    }

    #[test]
    fn preview_replaces_images_over_the_per_image_size_limit() {
        let directory =
            std::env::temp_dir().join(format!("md-engine-preview-limit-{}", uuid_for_test()));
        std::fs::create_dir_all(&directory).expect("create fixture directory");
        std::fs::write(
            directory.join("large.png"),
            vec![0; MAX_PREVIEW_IMAGE_BYTES as usize + 1],
        )
        .expect("write oversized image fixture");
        let options = RenderOptions {
            base_dir: Some(directory.clone()),
            allowed_root_dir: Some(directory.clone()),
            embed_local_images: true,
            ..RenderOptions::default()
        };

        let output = render_markdown("![large](large.png)", &options).expect("render should pass");
        assert!(!output.html.contains("src=\"data:"));
        assert!(output.html.contains("Image exceeds Quick Look size limit"));
        assert_eq!(output.diagnostics.len(), 1);

        std::fs::remove_dir_all(directory).expect("remove fixture directory");
    }

    fn uuid_for_test() -> String {
        use std::time::{SystemTime, UNIX_EPOCH};
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock")
            .as_nanos()
            .to_string()
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
