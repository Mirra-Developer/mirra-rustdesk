use super::*;
use crate::{flutter::FlutterHandler, ui_session_interface::Session};
use hbb_common::{tcp::FramedStream, tokio::net::TcpListener};

#[tokio::test]
async fn auto_id_requests_retain_credentials_and_propagate_authorization_errors() {
    crate::auto_id::initialize_test_app();
    for error in ["must-login", "permission denied"] {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap().to_string();
        let token = "synthetic-account-credential";
        let server = tokio::spawn(async move {
            let (socket, address) = listener.accept().await.unwrap();
            let mut stream = FramedStream::from(socket, address);
            let bytes = stream.next().await.unwrap().unwrap();
            let request = RendezvousMessage::parse_from_bytes(&bytes).unwrap();
            assert!(request.punch_hole_request().token == token);
            assert_eq!(request.punch_hole_request().id, "123");
            let mut response = RendezvousMessage::new();
            response.set_punch_hole_response(PunchHoleResponse {
                other_failure: error.to_owned(),
                ..Default::default()
            });
            stream.send(&response).await.unwrap();
        });
        let session = Session::<FlutterHandler>::default();
        session.lc.write().unwrap().id = "123".to_owned();
        let result = Client::_start_inner(
            "123".to_owned(),
            String::new(),
            token.to_owned(),
            ConnType::DEFAULT_CONN,
            session,
            (None, None),
            None,
            None,
            None,
            address,
            Vec::new(),
            true,
        )
        .await;
        assert!(matches!(result, Err(ref actual) if actual.to_string() == error));
        server.await.unwrap();
    }
}

#[test]
fn auto_id_password_errors_keep_the_original_device_login_flow() {
    crate::auto_id::initialize_test_app();
    let session = Session::<FlutterHandler>::default();
    {
        let mut login = session.lc.write().unwrap();
        login.id = "123".to_owned();
        login.password = vec![1, 2, 3];
        login.remember = true;
    }
    assert!(Interface::handle_login_error(&session, LOGIN_MSG_PASSWORD_WRONG));
    {
        let login = session.lc.read().unwrap();
        assert!(login.password.is_empty());
        assert!(login.remember);
        assert!(login.other_server.is_none());
        assert_eq!(login.id, "123");
    }
    assert!(!Interface::handle_login_error(&session, "permission denied"));
}
