use axum::{
    extract::State,
    http::StatusCode,
    response::{Html, IntoResponse, Response},
};
use std::path::Path;

use crate::state::AppState;

pub async fn root_handler(State(state): State<AppState>) -> impl IntoResponse {
    serve_page(&state.webroot, "update.html").await
}

pub async fn custom_handler(State(state): State<AppState>) -> impl IntoResponse {
    serve_page(&state.webroot, "index.html").await
}

pub async fn backup_handler(State(state): State<AppState>) -> impl IntoResponse {
    serve_page(&state.webroot, "backup.html").await
}

pub async fn update_handler(State(state): State<AppState>) -> impl IntoResponse {
    serve_page(&state.webroot, "update.html").await
}

pub async fn fpga_handler(State(state): State<AppState>) -> impl IntoResponse {
    serve_page(&state.webroot, "fpga.html").await
}

pub async fn pihpsdr_handler(State(state): State<AppState>) -> impl IntoResponse {
    serve_page(&state.webroot, "pihpsdr.html").await
}

pub async fn monitor_handler(State(state): State<AppState>) -> impl IntoResponse {
    serve_page(&state.webroot, "monitor.html").await
}

pub async fn healthz() -> impl IntoResponse {
    StatusCode::OK
}

pub fn route_to_page(path: &str) -> Option<&'static str> {
    match path {
        "/" | "/saturn" | "/saturn/" => Some("update.html"),
        "/custom" | "/custom/" | "/custom.html" | "/index" | "/index.html" | "/saturn/custom"
        | "/saturn/custom/" | "/saturn/custom.html" | "/saturn/index"
        | "/saturn/index.html" => Some("index.html"),
        "/backup" | "/backup/" | "/backup.html" | "/saturn/backup" | "/saturn/backup/"
        | "/saturn/backup.html" => Some("backup.html"),
        "/update" | "/update/" | "/update.html" | "/saturn/update" | "/saturn/update/"
        | "/saturn/update.html" => Some("update.html"),
        "/fpga" | "/fpga/" | "/fpga.html" | "/saturn/fpga" | "/saturn/fpga/"
        | "/saturn/fpga.html" => Some("fpga.html"),
        "/pihpsdr" | "/pihpsdr/" | "/pihpsdr.html" | "/saturn/pihpsdr" | "/saturn/pihpsdr/"
        | "/saturn/pihpsdr.html" => Some("pihpsdr.html"),
        "/monitor" | "/monitor/" | "/monitor.html" | "/saturn/monitor" | "/saturn/monitor/"
        | "/saturn/monitor.html" => Some("monitor.html"),
        _ => None,
    }
}

pub async fn fallback_handler(
    State(state): State<AppState>,
    axum::extract::OriginalUri(uri): axum::extract::OriginalUri,
) -> impl IntoResponse {
    if let Some(page) = route_to_page(uri.path()) {
        return serve_page(&state.webroot, page).await;
    }
    (StatusCode::NOT_FOUND, "Not Found").into_response()
}

pub async fn serve_page(webroot: &Path, page: &str) -> Response {
    let page_path = webroot.join(page);
    match tokio::fs::read_to_string(&page_path).await {
        Ok(body) => Html(body).into_response(),
        Err(_) => (StatusCode::NOT_FOUND, "page not found").into_response(),
    }
}
