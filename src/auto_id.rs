use crate::{
    auto_id_config::{self, RoutingConfig, API_ORIGIN},
    auto_id_policy::{select_server, OnlineState, Resolution},
    auto_id_query::query_regions,
};
use hbb_common::{
    bail,
    config::{self, Config, LocalConfig},
    log, ResultType,
};
use std::sync::Once;

pub const TEST_APP_NAME: &str = "MirraRustDeskTest";
static INITIALIZE: Once = Once::new();

pub fn initialize_test_app() {
    if option_env!("MIRRA_TEST_APP") == Some("1") {
        INITIALIZE.call_once(|| {
            *config::APP_NAME.write().unwrap() = TEST_APP_NAME.to_owned();
            config::HARD_SETTINGS
                .write()
                .unwrap()
                .insert("disable-installation".to_owned(), "Y".to_owned());
        });
    }
}

pub fn enabled() -> bool {
    option_env!("MIRRA_TEST_APP") == Some("1")
        && Config::get_option("mirra-auto-id-routing") == "Y"
        && auto_id_config::load()
            .map(|config| config.enabled)
            .unwrap_or(true)
}

pub fn is_numeric_id(id: &str) -> bool {
    !id.is_empty() && id.bytes().all(|byte| byte.is_ascii_digit())
}

pub struct Route<'a> {
    pub server: String,
    pub public_key: String,
    pub token: &'a str,
}

fn require_account(token: &str, api_origin: &str) -> ResultType<()> {
    if token.is_empty() {
        bail!("Please log in to Account before connecting.");
    }
    if api_origin.trim_end_matches('/') != API_ORIGIN {
        bail!("Automatic ID routing requires the configured Mirra Account service.");
    }
    Ok(())
}

pub async fn resolve<'a>(id: &str, token: &'a str) -> ResultType<Option<Route<'a>>> {
    if !enabled() || !is_numeric_id(id) {
        return Ok(None);
    }
    require_account(token, &crate::ui_interface::get_api_server())?;
    route_with_config(&auto_id_config::load()?, id, token)
        .await
        .map(Some)
}

async fn route_with_config<'a>(
    config: &RoutingConfig,
    id: &str,
    token: &'a str,
) -> ResultType<Route<'a>> {
    let assigned = config.assigned_index(id);
    let resolution = if let Some(index) = assigned {
        Resolution::Selected(index)
    } else {
        let regions = query_regions(&config.servers, &[id.to_owned()]).await;
        select_server(&regions.iter().map(|states| states[0]).collect::<Vec<_>>())
    };
    match resolution {
        Resolution::Selected(index) => {
            let service = &config.servers[index];
            let mode = if assigned.is_some() { "manual" } else { "auto" };
            log::info!(
                "Automatic ID route: peer={id}, server={}, mode={mode}",
                service.host
            );
            Ok(Route {
                server: service.host.clone(),
                public_key: service.public_key.clone(),
                token,
            })
        }
        Resolution::Conflict => bail!("Device ID is online on multiple configured ID servers."),
        Resolution::Offline => bail!("Remote desktop is offline"),
        Resolution::Unavailable => bail!("Unable to confirm the device's regional ID server."),
    }
}

pub async fn online_states<F: FnOnce(Vec<String>, Vec<String>)>(ids: Vec<String>, f: F) {
    if require_account(
        &LocalConfig::get_option("access_token"),
        &crate::ui_interface::get_api_server(),
    )
    .is_err()
    {
        f(Vec::new(), ids);
        return;
    }
    let config = match auto_id_config::load() {
        Ok(config) => config,
        Err(error) => {
            log::error!("Invalid connection routing configuration: {error}");
            f(Vec::new(), ids);
            return;
        }
    };
    let regions = query_regions(&config.servers, &ids).await;
    let mut onlines = Vec::new();
    let mut offlines = Vec::new();
    for (index, id) in ids.into_iter().enumerate() {
        let states: Vec<_> = regions.iter().map(|states| states[index]).collect();
        let online = match config.assigned_index(&id) {
            Some(service) => states[service] == OnlineState::Online,
            None => matches!(select_server(&states), Resolution::Selected(_)),
        };
        if online {
            onlines.push(id);
        } else {
            offlines.push(id);
        }
    }
    f(onlines, offlines);
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::tokio::{
        self,
        time::{timeout, Duration},
    };

    #[test]
    fn account_credentials_are_required_and_confined_to_the_trusted_api() {
        assert!(require_account("", API_ORIGIN).is_err());
        assert!(require_account("test-credential", "https://untrusted.invalid").is_err());
        assert!(require_account("test-credential", API_ORIGIN).is_ok());
        assert!(require_account("test-credential", &format!("{API_ORIGIN}/")).is_ok());
    }

    #[tokio::test]
    async fn auto_id_manual_route_preserves_id_key_and_token_without_online_query() {
        let mut config = RoutingConfig::default();
        config.servers[1].host = "unreachable.invalid".into();
        config.device_routes.insert("123".into(), "cn".into());
        let route = timeout(
            Duration::from_millis(100),
            route_with_config(&config, "123", "synthetic-token"),
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(route.server, "unreachable.invalid");
        assert_eq!(route.public_key, config.servers[1].public_key);
        assert_eq!(route.token, "synthetic-token");
    }

    #[tokio::test]
    #[ignore = "read-only live check; requires the four test devices to be online"]
    async fn live_four_devices_use_their_registered_regional_servers() {
        initialize_test_app();
        let ids: Vec<String> = std::env::var("MIRRA_LIVE_TEST_IDS")
            .expect("Set MIRRA_LIVE_TEST_IDS to two US IDs followed by two China IDs")
            .split(',')
            .map(|id| id.trim().to_owned())
            .collect();
        assert_eq!(ids.len(), 4, "Supply exactly four test IDs");
        assert!(ids.iter().all(|id| is_numeric_id(id)));
        let config = auto_id_config::load().unwrap();
        let regions = query_regions(&config.servers, &ids).await;
        let token = LocalConfig::get_option("access_token");
        for (index, id) in ids.iter().enumerate() {
            let states: Vec<_> = regions.iter().map(|states| states[index]).collect();
            let expected = if index < 2 { 0 } else { 1 };
            assert_eq!(
                select_server(&states),
                Resolution::Selected(expected),
                "{id}"
            );
            if !token.is_empty() {
                let route = resolve(id, &token).await.unwrap().unwrap();
                assert!(route.token == token);
                assert!(route.token.as_ptr() == token.as_ptr());
                assert_eq!(route.server, config.servers[expected].host);
                assert_eq!(route.public_key, config.servers[expected].public_key);
            }
            println!("{id}: {}", config.servers[expected].host);
        }
    }
}
