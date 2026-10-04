use hbb_common::{bail, base64, config::LocalConfig, ResultType};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashSet};

pub const OPTION: &str = "mirra-id-routing-v1";
pub const API_ORIGIN: &str = "https://rustdesk.mirra-xr.com";
const DEFAULT_KEY: &str = "QmfG5xMJbd52Bev1msSG8Vfe+RVRKXQD98NkQGc1gJg=";

#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct IdService {
    pub id: String,
    pub name: String,
    pub host: String,
    pub public_key: String,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RoutingConfig {
    pub version: u8,
    pub enabled: bool,
    pub servers: Vec<IdService>,
    pub device_routes: BTreeMap<String, String>,
}

impl Default for RoutingConfig {
    fn default() -> Self {
        Self {
            version: 1,
            enabled: true,
            servers: [
                ("us", "美国", "us.rustdesk.mirra-xr.com"),
                ("cn", "中国", "rustdesk.mirra-xr.com"),
            ]
            .into_iter()
            .map(|(id, name, host)| IdService {
                id: id.to_owned(),
                name: name.to_owned(),
                host: host.to_owned(),
                public_key: DEFAULT_KEY.to_owned(),
            })
            .collect(),
            device_routes: BTreeMap::new(),
        }
    }
}

impl RoutingConfig {
    pub fn parse(value: &str) -> ResultType<Self> {
        let config: Self = if value.is_empty() {
            Self::default()
        } else {
            serde_json::from_str(value)?
        };
        config.validate()?;
        Ok(config)
    }

    pub fn validate(&self) -> ResultType<()> {
        if self.version != 1 || self.servers.is_empty() {
            bail!("Invalid connection routing configuration");
        }
        let mut ids = HashSet::new();
        let mut hosts = HashSet::new();
        for service in &self.servers {
            let host = service.host.as_str();
            let valid_host = host.len() <= 253
                && host.split('.').all(|part| {
                    !part.is_empty()
                        && part.len() <= 63
                        && !part.starts_with('-')
                        && !part.ends_with('-')
                        && part.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
                });
            if service.id.is_empty()
                || service.name.trim().is_empty()
                || !valid_host
                || !ids.insert(service.id.as_str())
                || !hosts.insert(host.to_ascii_lowercase())
                || base64::decode(&service.public_key)?.len() != 32
            {
                bail!("Invalid or duplicate ID service; use a hostname or IPv4 address and a 32-byte public key");
            }
        }
        for (peer, service) in &self.device_routes {
            if peer.is_empty()
                || !peer.bytes().all(|b| b.is_ascii_digit())
                || (!service.is_empty() && !ids.contains(service.as_str()))
            {
                bail!("Invalid device ID or missing assigned ID service");
            }
        }
        Ok(())
    }

    pub fn assigned_index(&self, peer: &str) -> Option<usize> {
        self.device_routes
            .get(peer)
            .and_then(|id| self.servers.iter().position(|service| &service.id == id))
    }
}

pub fn load() -> ResultType<RoutingConfig> {
    RoutingConfig::parse(&LocalConfig::get_option(OPTION))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auto_id_config_round_trip_keeps_assignments_through_rename_and_reorder() {
        let mut config = RoutingConfig::default();
        config.device_routes.insert("123".into(), "cn".into());
        config.servers[1].name = "China office".into();
        config.servers.reverse();
        let loaded = RoutingConfig::parse(&serde_json::to_string(&config).unwrap()).unwrap();
        assert_eq!(loaded.assigned_index("123"), Some(0));
        assert_eq!(loaded.assigned_index("456"), None);
        assert_eq!(loaded.servers[0].name, "China office");
        config.servers.remove(0);
        assert!(config.validate().is_err());
    }

    #[test]
    fn auto_id_config_rejects_invalid_or_duplicate_services_without_fallback() {
        assert!(RoutingConfig::parse("broken").is_err());
        for field in ["host", "public_key", "id"] {
            let mut value = serde_json::to_value(RoutingConfig::default()).unwrap();
            value["servers"][0][field] = match field {
                "host" => "https://example.com".into(),
                "public_key" => "bad-key".into(),
                _ => "cn".into(),
            };
            assert!(RoutingConfig::parse(&value.to_string()).is_err());
        }
    }
}
