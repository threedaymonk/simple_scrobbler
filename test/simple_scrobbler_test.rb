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

  def setup
    FakeWeb.clean_registry
    FakeWeb.allow_net_connect = false
  end

  def gettoken_response
    <<-END
      <lfm status="ok">
        <token>cf45fe5a3e3cebe168480a086d7fe481</token>
      </lfm>
    END
  end

  def getsession_response
    <<-END
      <lfm status="ok">
        <session>
          <name>MyLastFMUsername</name>
          <key>d580d57f32848f5dcf574d1ce18d78b2</key>
          <subscriber>0</subscriber>
        </session>
      </lfm>
    END
  end

  attr_reader :ss

  def setup_scrobbler_without_session
    @ss = SimpleScrobbler.new("APIXXX", "SECRETXXX", "userxxx")
  end

  def ws_endpoint
    "http://ws.audioscrobbler.com/2.0/"
  end

  def stub_gettoken_response
    ss.stubs(:get).
       with(ws_endpoint,
            has_entry("method" => "auth.gettoken")).
       returns(gettoken_response)
  end

  def stub_getsession_response
    ss.stubs(:get).
       with(ws_endpoint,
            has_entry("method" => "auth.getsession")).
       returns(getsession_response)
  end

  def test_should_make_signed_gettoken_request
    setup_scrobbler_without_session
    ss.expects(:get).
       with(ws_endpoint,
            "api_key" => "APIXXX",
            "method"  => "auth.gettoken",
            "api_sig" => "365b45edb0f6e1b9e681375e787af0f0").
       returns(gettoken_response)
    stub_getsession_response
    ss.fetch_session_key{}
  end

  def test_should_yield_auth_url
    setup_scrobbler_without_session
    stub_gettoken_response
    stub_getsession_response
    ss.fetch_session_key do |auth_url|
      assert_equal "http://www.last.fm/api/auth/?api_key=APIXXX&token=cf45fe5a3e3cebe168480a086d7fe481", auth_url
    end
  end

  def test_should_get_session_using_token_after_user_authenticates
    setup_scrobbler_without_session
    stub_gettoken_response
    ss.stubs(:get).
       with("http://ws.audioscrobbler.com/2.0/",
            "api_key" => "APIXXX",
            "method"  => "auth.getsession",
            "token"   => "cf45fe5a3e3cebe168480a086d7fe481",
            "api_sig" => "cb155d6f313b229a8445ff14a8e15082").
       returns(getsession_response)
    session_key = ss.fetch_session_key do |auth_url|
      # assume that user has visited auth_url
    end
    assert_equal "d580d57f32848f5dcf574d1ce18d78b2", session_key
  end

  def test_should_set_session_key_and_user_from_auth_response
    setup_scrobbler_without_session
    stub_gettoken_response
    stub_getsession_response
    ss.fetch_session_key{}
    assert_equal "d580d57f32848f5dcf574d1ce18d78b2", ss.session_key
    assert_equal "MyLastFMUsername", ss.user
  end

  def test_should_raise_a_session_error_if_submit_is_called_without_a_session_key
    setup_scrobbler_without_session
    assert_raises SimpleScrobbler::SessionError do
      ss.submit("Sex Pistols", "Anarchy in the UK", :length => 211)
    end
  end

  def handshake_ok_response
    [ "OK",
      "17E61E13454CDD8B68E8D7DEEEDF6170",
      "http://post.audioscrobbler.com:80/np_1.2",
      "http://post2.audioscrobbler.com:80/protocol_1.2" ].join("\n")
  end

  def setup_scrobbler_with_session
    @ss = SimpleScrobbler.new("APIXXX", "SECRETXXX", "userxxx", "SESSIONXXX")
  end

  def test_should_handshake
    Time.stubs(:now).returns(Time.at(1278776195))
    setup_scrobbler_with_session
    ss.expects(:get).
       with("http://post.audioscrobbler.com/",
            "a"       => "2fc94a957c7def6846bb334b3e7913f6",
            "api_key" => "APIXXX",
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
       with("http://post.audioscrobbler.com/",
            has_entry("hs" => "true")).
       returns(response)
  end

  def test_should_submit_a_scrobble
    Time.stubs(:now).returns(Time.at(1278776195))
    setup_scrobbler_with_session
    stub_handshake handshake_ok_response
    ss.expects(:post).
       with("http://post2.audioscrobbler.com:80/protocol_1.2",
            "i[0]" => "1278776195",
            "t[0]" => "Anarchy in the UK",
            "a[0]" => "Sex Pistols",
            "n[0]" => "",
            "r[0]" => "",
            "o[0]" => "P",
            "s"    => "17E61E13454CDD8B68E8D7DEEEDF6170",
            "m[0]" => "",
            "b[0]" => "",
            "l[0]" => "211").
       returns("OK\n")
    ss.submit("Sex Pistols", "Anarchy in the UK", :length => 3*60+31)
  end

  def test_should_handshake_automatically_once
    setup_scrobbler_with_session
    ss.expects(:get).
       with("http://post.audioscrobbler.com/",
            has_entry("hs" => "true")).
       times(1).
       returns(handshake_ok_response)
    ss.stubs(:post).
       with("http://post2.audioscrobbler.com:80/protocol_1.2", anything).
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
       with("http://post2.audioscrobbler.com:80/protocol_1.2",
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
    ss.handshake
    ss.stubs(:post).
       with("http://post2.audioscrobbler.com:80/protocol_1.2", anything).
       returns("FAILED who knows why?\n")
    assert_raises SimpleScrobbler::SubmissionError do
      ss.submit("Sex Pistols", "Anarchy in the UK", :length => 211)
    end
  end

  def test_should_raise_data_error_if_length_is_missing_and_source_is_P
    setup_scrobbler_with_session
    stub_handshake handshake_ok_response
    ss.handshake
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

end
