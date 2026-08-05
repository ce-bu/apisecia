use clap::Parser;
use sqlx::postgres::PgPoolOptions;
use tower_http::trace::TraceLayer;
use tracing::{error, info, warn};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

// Define command line arguments with environment variable fallbacks
#[derive(Parser, Debug)]
#[command(
    name = "apisecia-backend",
    version = "0.1.0",
    about = "Production Axum API with automatic Postgres migrations"
)]
struct Args {
    /// Force running SQLx schema migrations automatically on application boot
    #[arg(short = 'f', long = "force-migrate", default_value_t = false)]
    force_migrate: bool,

    /// Explicitly override the server binding port
    #[arg(short = 'p', long = "port", default_value = "4567")]
    port: u16,

    /// Database connection URL (Falls back to DATABASE_URL env var)
    #[arg(
        long = "database-url",
        env = "DATABASE_URL",
        default_value = "postgres://user:user@localhost:5432/apisecia"
    )]
    database_url: String,

    /// Structured logging filter layout (Falls back to RUST_LOG env var)
    #[arg(
        long = "log-level",
        env = "RUST_LOG",
        default_value = "apisecia=info,axum=info,sqlx=warn,tower_http=info"
    )]
    log_level: String,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    dotenvy::dotenv().ok();

    let args = Args::parse();

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_new(&args.log_level)
                .unwrap_or_else(|_| "apisecia=info,axum=info,sqlx=warn,tower_http=info".into()),
        )
        .with(tracing_subscriber::fmt::layer().with_target(true))
        .init();

    info!("Initializing Apisecia server subsystem...");

    /*
           info!("Connecting to PostgreSQL cluster resource...");
           let pool = match PgPoolOptions::new()
               .max_connections(5)
               .acquire_timeout(std::time::Duration::from_secs(3))
               .connect(&args.database_url)
               .await
           {
               Ok(p) => {
                   info!("Database connection pool established successfully.");
                   p
               }
               Err(e) => {
                   error!("Failed to establish database connection: {}", e);
                   return Err(e.into());
               }
           };


           if args.force_migrate {
               warn!("⚠️  Force-migrate flag (-f) detected. Checking and applying database schemas...");
               match sqlx::migrate!("./migrations").run(&pool).await {
                   Ok(_) => info!("Database schemas are fully updated and synchronized."),
                   Err(e) => {
                       error!("Critical migration phase breakdown: {}", e);
                       return Err(e.into());
                   }
               }
           } else {
               info!("Skipping boot-time database migrations (run with -f to enable).");
           }

       let app = axum::Router::new()
           .route("/health", axum::routing::get(|| async { "OK" }))
           .layer(TraceLayer::new_for_http())
           .with_state(pool);
    */

    let addr = format!("127.0.0.1:{}", args.port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;

    info!("axum server listen at", addr = %addr);

    axum::serve(listener, app).await?;

    Ok(())
}
