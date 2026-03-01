use axum::{
    body::Body,
    http::{header, HeaderMap, Method, Request, StatusCode},
    middleware::Next,
    response::Response,
};

use crate::state::{AppState, CSRF_HEADER_NAME, CSRF_HEADER_VALUE};
use crate::util::json_error;

fn is_safe_method(method: &Method) -> bool {
    matches!(
        *method,
        Method::GET | Method::HEAD | Method::OPTIONS | Method::TRACE
    )
}

fn parse_host_from_authority(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    let authority = trimmed.rsplit('@').next().unwrap_or(trimmed).trim();
    if authority.is_empty() {
        return None;
    }
    if authority.starts_with('[') {
        let end = authority.find(']')?;
        return Some(authority[..=end].to_ascii_lowercase());
    }
    let host = authority
        .split(':')
        .next()
        .unwrap_or("")
        .trim()
        .to_ascii_lowercase();
    if host.is_empty() {
        None
    } else {
        Some(host)
    }
}

fn parse_host_from_url(value: &str) -> Option<String> {
    let trimmed = value.trim();
    let scheme_pos = trimmed.find("://")?;
    let rest = &trimmed[scheme_pos + 3..];
    let authority = rest.split('/').next().unwrap_or("");
    parse_host_from_authority(authority)
}

fn get_request_host(headers: &HeaderMap) -> Option<String> {
    headers
        .get(header::HOST)
        .and_then(|v| v.to_str().ok())
        .and_then(parse_host_from_authority)
}

fn get_source_host(headers: &HeaderMap) -> Option<String> {
    if let Some(origin) = headers.get(header::ORIGIN).and_then(|v| v.to_str().ok()) {
        if !origin.eq_ignore_ascii_case("null") {
            if let Some(host) = parse_host_from_url(origin) {
                return Some(host);
            }
        }
    }
    headers
        .get(header::REFERER)
        .and_then(|v| v.to_str().ok())
        .and_then(parse_host_from_url)
}

pub async fn csrf_protect(
    axum::extract::State(_state): axum::extract::State<AppState>,
    req: Request<Body>,
    next: Next,
) -> Response {
    if is_safe_method(req.method()) {
        return next.run(req).await;
    }

    let headers = req.headers();
    let csrf = headers
        .get(CSRF_HEADER_NAME)
        .and_then(|v| v.to_str().ok())
        .map(str::trim);
    if csrf != Some(CSRF_HEADER_VALUE) {
        return json_error(StatusCode::FORBIDDEN, "missing or invalid CSRF header");
    }

    let req_host = match get_request_host(headers) {
        Some(v) => v,
        None => return json_error(StatusCode::BAD_REQUEST, "missing Host header"),
    };
    match get_source_host(headers) {
        Some(source_host) => {
            if source_host != req_host {
                return json_error(StatusCode::FORBIDDEN, "Origin/Referer host mismatch");
            }
        }
        None => {
            return json_error(StatusCode::FORBIDDEN, "missing Origin or Referer header");
        }
    }

    next.run(req).await
}
