use crate::{
    auto_id_config::IdService,
    auto_id_policy::{decode_online_states, OnlineState},
};
use hbb_common::{
    bail,
    config::Config,
    futures::future::join_all,
    rendezvous_proto::{rendezvous_message, OnlineRequest, RendezvousMessage},
    socket_client::{check_port, connect_tcp},
    tokio::time::{timeout, Duration},
    ResultType,
};

const QUERY_TIMEOUT: Duration = Duration::from_secs(2);

async fn query_server(server: &str, ids: &[String]) -> ResultType<Vec<OnlineState>> {
    let query = async {
        let mut stream = connect_tcp(check_port(server, 21115), 2_000).await?;
        let mut request = RendezvousMessage::new();
        request.set_online_request(OnlineRequest {
            id: Config::get_id(),
            peers: ids.to_vec(),
            ..Default::default()
        });
        stream.send(&request).await?;
        if let Some(message) = crate::get_next_nonkeyexchange_msg(&mut stream, Some(2_000)).await {
            if let Some(rendezvous_message::Union::OnlineResponse(response)) = message.union {
                if let Some(states) = decode_online_states(&response.states, ids.len()) {
                    return Ok(states);
                }
            }
        }
        bail!("Invalid regional online response");
    };
    match timeout(QUERY_TIMEOUT, query).await {
        Ok(result) => result,
        Err(_) => bail!("Regional ID query timed out"),
    }
}

pub async fn query_regions(services: &[IdService], ids: &[String]) -> Vec<Vec<OnlineState>> {
    join_all(
        services
            .iter()
            .map(|service| query_server(&service.host, ids)),
    )
    .await
    .into_iter()
    .map(|result| match result {
        Ok(states) => states,
        Err(_) => vec![OnlineState::Unreachable; ids.len()],
    })
    .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::{
        protobuf::Message,
        rendezvous_proto::OnlineResponse,
        tcp::FramedStream,
        tokio::{self, net::TcpListener, time::Instant},
    };

    #[tokio::test]
    async fn online_queries_validate_responses_and_enforce_the_deadline() {
        crate::auto_id::initialize_test_app();
        for states in [Some(vec![0x80]), Some(vec![]), None] {
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let address = listener.local_addr().unwrap().to_string();
            let valid = states.as_deref() == Some(&[0x80]);
            let stalled = states.is_none();
            let server = tokio::spawn(async move {
                let (socket, address) = listener.accept().await.unwrap();
                let mut stream = FramedStream::from(socket, address);
                let bytes = stream.next().await.unwrap().unwrap();
                let request = RendezvousMessage::parse_from_bytes(&bytes).unwrap();
                assert_eq!(request.online_request().peers, ["123"]);
                if let Some(states) = states {
                    let mut response = RendezvousMessage::new();
                    response.set_online_response(OnlineResponse {
                        states: states.into(),
                        ..Default::default()
                    });
                    stream.send(&response).await.unwrap();
                } else {
                    std::future::pending::<()>().await;
                }
            });
            let started = Instant::now();
            let result = query_server(&address, &["123".to_owned()]).await;
            if valid {
                assert_eq!(result.unwrap(), [OnlineState::Online]);
            } else {
                assert!(result.is_err());
            }
            if stalled {
                assert!(started.elapsed() >= QUERY_TIMEOUT);
                assert!(started.elapsed() < Duration::from_millis(2_800));
                server.abort();
            } else {
                server.await.unwrap();
            }
        }
    }
}
