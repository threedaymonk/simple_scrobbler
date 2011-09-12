lib_path = File.expand_path("../../lib", __FILE__)
$:.unshift lib_path unless $:.include?(lib_path)
require "test/unit"
require "simple_scrobbler"
require "mocha"
require "fakeweb"

class SimpleScrobbler
  # Should probably use dependency injection instead
  public :get, :post
end

class SimpleScrobblerTest < Test::Unit::TestCase

  TOKEN               = "cf45fe5a3e3cebe168480a086d7fe481"
  USER_NAME           = "MyLastFMUsername"
  SESSION_KEY         = "d580d57f32848f5dcf574d1ce18d78b2"
  API_KEY             = "APIXXX"
  SECRET              = "SECRETXXX"
  WS_ENDPOINT         = "http://ws.audioscrobbler.com/2.0/"
  HANDSHAKE_URL       = "http://post.audioscrobbler.com/"
  SCROBBLE_SESSION_ID = "17E61E13454CDD8B68E8D7DEEEDF6170"
  NOW_PLAYING_URL     = "http://post.audioscrobbler.com:80/np_1.2"
  SUBMISSION_URL      = "http://post2.audioscrobbler.com:80/protocol_1.2"
  GETTOKEN_RESPONSE   = %{<lfm status="ok">
                            <token>#{TOKEN}</token>
                          </lfm>}
  GETSESSION_RESPONSE = %{<lfm status="ok">
                            <session>
                              <name>#{USER_NAME}</name>
                              <key>#{SESSION_KEY}</key>
                              <subscriber>0</subscriber>
                            </session>
                          </lfm>}

  def setup
    FakeWeb.clean_registry
    FakeWeb.allow_net_connect = false
  end

  attr_reader :ss

  def setup_scrobbler_without_session
    @ss = SimpleScrobbler.new(API_KEY, SECRET, "userxxx")
  end

  def stub_gettoken_response
    ss.stubs(:get).
       with(WS_ENDPOINT,
            has_entry("method" => "auth.gettoken")).
       returns(GETTOKEN_RESPONSE)
  end

  def stub_getsession_response
    ss.stubs(:get).
       with(WS_ENDPOINT,
            has_entry("method" => "auth.getsession")).
       returns(GETSESSION_RESPONSE)
  end

  def test_should_make_signed_gettoken_request
    setup_scrobbler_without_session
    ss.expects(:get).
       with(WS_ENDPOINT,
            "api_key" => API_KEY,
            "method"  => "auth.gettoken",
            "api_sig" => "365b45edb0f6e1b9e681375e787af0f0").
       returns(GETTOKEN_RESPONSE)
    stub_getsession_response
    ss.fetch_session_key{}
  end

  def test_should_yield_auth_url
    setup_scrobbler_without_session
    stub_gettoken_response
    stub_getsession_response
    ss.fetch_session_key do |auth_url|
      assert_equal "http://www.last.fm/api/auth/?api_key=#{API_KEY}&token=#{TOKEN}", auth_url
    end
  end

  def test_should_get_session_using_token_after_user_authenticates
    setup_scrobbler_without_session
    stub_gettoken_response
    ss.stubs(:get).
       with(WS_ENDPOINT,
            "api_key" => API_KEY,
            "method"  => "auth.getsession",
            "token"   => TOKEN,
            "api_sig" => "cb155d6f313b229a8445ff14a8e15082").
       returns(GETSESSION_RESPONSE)
    session_key = ss.fetch_session_key do |auth_url|
      # assume that user has visited auth_url
    end
    assert_equal SESSION_KEY, session_key
  end

  def test_should_set_session_key_and_user_from_auth_response
    setup_scrobbler_without_session
    stub_gettoken_response
    stub_getsession_response
    ss.fetch_session_key{}
    assert_equal SESSION_KEY, ss.session_key
    assert_equal USER_NAME, ss.user
  end

  def test_should_raise_a_session_error_if_submit_is_called_without_a_session_key
    setup_scrobbler_without_session
    assert_raises SimpleScrobbler::SessionError do
      ss.submit("Sex Pistols", "Anarchy in the UK", :length => 211)
    end
  end

  def handshake_ok_response
    [ "OK",
      SCROBBLE_SESSION_ID,
      NOW_PLAYING_URL,
      SUBMISSION_URL ].join("\n")
  end

  def setup_scrobbler_with_session
    @ss = SimpleScrobbler.new(API_KEY, SECRET, "userxxx", "SESSIONXXX")
  end

  def test_should_handshake
    Time.stubs(:now).returns(Time.at(1278776195))
    setup_scrobbler_with_session
    ss.expects(:get).
       with(HANDSHAKE_URL,
            "a"       => "2fc94a957c7def6846bb334b3e7913f6",
            "api_key" => API_KEY,
            "c"       => "tst",
            "hs"      => "true",
            "p"       => "1.2.1",
            "sk"      => "SESSIONXXX",
            "t"       => "1278776195",
            "u"       => "userxxx",
            "v"       => "1.0").
       returns(handshake_ok_response)
    ss.handshake
  end

  def stub_handshake(response)
    ss.stubs(:get).
       with(HANDSHAKE_URL,
            has_entry("hs" => "true")).
       returns(response)
  end

  def test_should_submit_a_minimal_scrobble
    Time.stubs(:now).returns(Time.at(1278776195))
    setup_scrobbler_with_session
    stub_handshake handshake_ok_response
    ss.expects(:post).
       with(SUBMISSION_URL,
            "i[0]" => "1278776195",
            "t[0]" => "Anarchy in the UK",
            "a[0]" => "Sex Pistols",
            "n[0]" => "",
            "r[0]" => "",
            "o[0]" => "P",
            "s"    => SCROBBLE_SESSION_ID,
            "m[0]" => "",
            "b[0]" => "",
            "l[0]" => "211").
       returns("OK\n")
    ss.submit("Sex Pistols", "Anarchy in the UK", :length => 3*60+31)
  end

  def test_should_submit_a_full_scrobble
    setup_scrobbler_with_session
    stub_handshake handshake_ok_response
    ss.expects(:post).
       with(SUBMISSION_URL,
            "s"    => SCROBBLE_SESSION_ID,
            "i[0]" => "1278776000",
            "a[0]" => "Sa Dingding",
            "t[0]" => "Hua",
            "b[0]" => "Harmony",
            "l[0]" => "298",
            "n[0]" => "3",
            "o[0]" => "P",
            "r[0]" => "",
            "m[0]" => "9999").
       returns("OK\n")
    ss.submit("Sa Dingding", "Hua",
              :album        => "Harmony",
              :length       => 4*60+58,
              :track_number => 3,
              :time         => Time.at(1278776000),
              :mb_trackid   => 9999)
  end

  def test_should_handshake_automatically_once
    setup_scrobbler_with_session
    ss.expects(:get).
       with(HANDSHAKE_URL,
            has_entry("hs" => "true")).
       times(1).
       returns(handshake_ok_response)
    ss.stubs(:post).
       with(SUBMISSION_URL, anything).
       returns("OK\n")
    2.times do
      ss.submit("Sex Pistols", "Anarchy in the UK", :length => 211)
    end
  end

  def test_should_submit_a_scrobble_with_a_different_source
    setup_scrobbler_with_session
    stub_handshake handshake_ok_response
    ss.source = "R"
    ss.expects(:post).
       with(SUBMISSION_URL,
            has_entry("o[0]" => "R")).
       returns("OK\n")
    ss.submit("Sex Pistols", "Anarchy in the UK")
  end

  def test_should_raise_handshake_error_if_handshake_response_is_not_ok
    setup_scrobbler_with_session
    stub_handshake "BANNED"
    assert_raises SimpleScrobbler::HandshakeError do
      ss.handshake
    end
  end

  def test_should_raise_submission_error_if_submit_response_is_not_ok
    setup_scrobbler_with_session
    stub_handshake handshake_ok_response
    ss.stubs(:post).
       with(SUBMISSION_URL, anything).
       returns("FAILED who knows why?\n")
    assert_raises SimpleScrobbler::SubmissionError do
      ss.submit("Sex Pistols", "Anarchy in the UK", :length => 211)
    end
  end

  def test_should_raise_data_error_if_length_is_missing_and_source_is_P
    setup_scrobbler_with_session
    stub_handshake handshake_ok_response
    ss.source = "P"
    assert_raises SimpleScrobbler::DataError do
      ss.submit("Sex Pistols", "Anarchy in the UK")
    end
  end

  def test_should_raise_data_error_if_source_is_set_to_unknown_value
    setup_scrobbler_with_session
    assert_raises SimpleScrobbler::DataError do
      ss.source = "Q"
    end
  end

  def test_should_raise_data_error_if_unknown_key_is_sent_to_submit
    setup_scrobbler_with_session
    stub_handshake handshake_ok_response
    assert_raises SimpleScrobbler::DataError do
      ss.submit("Sex Pistols", "Anarchy in the UK", :length => 211, :foo => "bar")
    end
  end

  def test_should_send_minimal_now_playing_details
    setup_scrobbler_with_session
    stub_handshake handshake_ok_response
    ss.expects(:post).
       with(NOW_PLAYING_URL,
            "s" => SCROBBLE_SESSION_ID,
            "a" => "Sex Pistols",
            "t" => "Anarchy in the UK",
            "b" => "",
            "l" => "",
            "n" => "",
            "m" => "").
       returns("OK\n")
    ss.now_playing("Sex Pistols", "Anarchy in the UK")
  end

  def test_should_send_full_now_playing_details
    setup_scrobbler_with_session
    stub_handshake handshake_ok_response
    ss.expects(:post).
       with(NOW_PLAYING_URL,
            "s" => SCROBBLE_SESSION_ID,
            "a" => "Sa Dingding",
            "t" => "Hua",
            "b" => "Harmony",
            "l" => "298",
            "n" => "3",
            "m" => "9999").
       returns("OK\n")
    ss.now_playing("Sa Dingding", "Hua",
                   :album        => "Harmony",
                   :length       => 4*60+58,
                   :track_number => 3,
                   :mb_trackid   => 9999)
  end

  def test_should_raise_submission_error_if_now_playing_response_is_not_ok
    setup_scrobbler_with_session
    stub_handshake handshake_ok_response
    ss.stubs(:post).
       with(NOW_PLAYING_URL, anything).
       returns("BADSESSION\n")
    assert_raises SimpleScrobbler::SubmissionError do
      ss.now_playing("Sex Pistols", "Anarchy in the UK")
    end
  end

  def test_should_raise_data_error_if_unknown_key_is_sent_to_now_playing
    setup_scrobbler_with_session
    stub_handshake handshake_ok_response
    assert_raises SimpleScrobbler::DataError do
      ss.now_playing("Sex Pistols", "Anarchy in the UK", :foo => "bar")
    end
  end

  def test_should_make_get_request_using_escaped_parameters_and_return_body
    setup_scrobbler_with_session
    Net::HTTP.expects(:get_response).
              with(URI.parse("http://example.com/?bar=1&foo=%25")).
              returns(stub(:body => "BODY"))
    body = ss.get("http://example.com/", "foo" => "%", "bar" => 1)
    assert_equal "BODY", body
  end

  def test_should_make_post_form_request_using_parameters_and_return_body
    setup_scrobbler_with_session
    Net::HTTP.expects(:post_form).
              with(URI.parse("http://example.com/"),
                   "foo" => "bar").
              returns(stub(:body => "BODY"))
    body = ss.post("http://example.com/", "foo" => "bar")
    assert_equal "BODY", body
  end

  def test_should_yield_profile_url_when_user_has_been_specified
    yielded = nil
    SimpleScrobbler.new(:api_key, :secret, 'last_fm_user').with_profile_url {|url| yielded = url }
    assert_equal 'http://www.last.fm/user/last_fm_user', yielded
  end
end
