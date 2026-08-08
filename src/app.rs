use axum::{Json, response::IntoResponse};
use axum_valid::Valid;
use serde::Deserialize;
use validator::Validate;

#[derive(Debug, Deserialize, Validate)]
struct CreateSpace {
    #[validate(length(
        min = 3,
        max = 20,
        message = "Name must be between 3 and 20 characters"
    ))]
    name: String,
    #[validate(length(
        min = 3,
        max = 50,
        message = "Owner must be between 3 and 50 characters"
    ))]
    owner: String,
}

async fn create_space(Valid(Json(payload)): Valid<Json<CreateSpace>>) -> impl IntoResponse {
    todo!()
}

pub fn create_app() -> axum::Router {
    let app =
        axum::Router::new().route("/spaces", axum::routing::post(|| async { "Hello, World!" }));

    app
}
