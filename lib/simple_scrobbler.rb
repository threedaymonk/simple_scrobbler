require "net/http"
require "digest/md5"
require "uri"
require "cgi"
require "rexml/document"
require "rexml/xpath"
require "simple_scrobbler/version"

class SimpleScrobbler
  CLIENT_ID      = "tst"
  CLIENT_VERSION = "1.0"

  HandshakeError  = Class.new(RuntimeError)
  SubmissionError = Class.new(RuntimeError)
  DataError       = Class.new(RuntimeError)
  SessionError    = Class.new(RuntimeError)

  # Instantiate a new SimpleScrobbler instance. If the session key is not
  # supplied, it must be fetched using fetch_session_key before scrobbling is
  # attempted.
  #
  # Your own API key and secret can be obtained from
  # http://www.last.fm/api/account
  #
  def initialize(api_key, secret, user, session_key=nil)
    @api_key     = api_key
    @secret      = secret
    @user        = user
    @session_key = session_key
    @source      = "P"
  end

  attr_reader :user, :api_key, :secret
  private :api_key, :secret

  def session_key
    @session_key or raise SessionError, "The session key must be set or fetched"
  end

  # The source of the track. Required, must be one of the following codes:
  # P :: Chosen by the user.
  # R :: Non-personalised broadcast (e.g. Shoutcast, BBC Radio 1).
  # E :: Personalised recommendation except Last.fm (e.g. Pandora, Launchcast).
  # L :: Last.fm (any mode).
  #
  def source=(a)
    unless %w[ P R E L ].include?(a)
      raise DataError, "source must be one of P, R, E, L (see http://www.last.fm/api/submissions)"
    end
    @source = a
  end

  # Fetch the auth key needed for the application. This can be stored and
  # supplied in the constructor on future occasions.
  #
  # Yields a URL which the user must visit. The block should not return until
  # this is done.
  #
  def fetch_session_key(&blk)
    doc = last_fm_web_service("method" => "auth.gettoken")
    request_token = doc.value_at("//token")

    yield "http://www.last.fm/api/auth/?api_key=#{api_key}&token=#{request_token}"

    doc = last_fm_web_service("method" => "auth.getsession", "token" => request_token)

    @session_key = doc.value_at("//key")
    @user        = doc.value_at("//name")

    @session_key
  end

  # Scrobble a track.
  #
  # The artist and track are required parameters. Other parameters can be added
  # as options:
  #
  # :time         :: Time at which the track started playing. Defaults to now
  # :length       :: Length of the track in seconds (required if the source is "P", the default)
  # :album        :: Album title
  # :track_number :: Track number
  # :mb_trackid   :: MusicBrainz Track ID
  #
  def submit(artist, track, options={})
    enforce_keys options, :time, :length, :album, :track_number, :mb_trackid
    if @source == "P" && !options[:length]
      raise DataError, "Track length must be specified if source is P"
    end
    handshake
    parameters =
      generate_scrobbling_parameters(true,
        options.merge(:artist => artist,
                      :track  => track,
                      :source => @source,
                      :time   => (options[:time] || Time.now).utc.to_i))
    status, = split_plain_text_response(post(@submission_url, parameters))
    raise SubmissionError, status unless status == "OK"
  end
  alias_method :scrobble, :submit

  # "The Now-Playing notification is a lightweight mechanism for notifying
  # Last.fm that a track has started playing. This is used for realtime display
  # of a user's currently playing track, and does not affect a user's musical
  # profile."
  #
  # The artist and track are required parameters. Other parameters can be added
  # as options:
  #
  # :length       :: Length of the track in seconds
  # :album        :: Album title
  # :track_number :: Track number
  # :mb_trackid   :: MusicBrainz Track ID
  #
  def now_playing(artist, track, options={})
    enforce_keys options, :length, :album, :track_number, :mb_trackid
    handshake
    parameters =
      generate_scrobbling_parameters(false,
        options.merge(:artist => artist, :track => track))
    status, = split_plain_text_response(post(@now_playing_url, parameters))
    raise SubmissionError, status unless status == "OK"
  end

  # Perform handshake with the API.
  #
  # There is usually no need to call this, as it will be called
  # automatically the first time a track is scrobbled.
  #
  def handshake
    return if @scrobble_session_id
    timestamp = Time.now.utc.to_i.to_s
    authentication_token = md5(secret + timestamp)
    parameters = {
      "hs"      => "true",
      "p"       => "1.2.1",
      "c"       => CLIENT_ID,
      "v"       => CLIENT_VERSION,
      "u"       => user,
      "t"       => timestamp,
      "a"       => authentication_token,
      "api_key" => api_key,
      "sk"      => session_key }
    body = get("http://post.audioscrobbler.com/", parameters)
    status,
    @scrobble_session_id,
    @now_playing_url,
    @submission_url, =
      split_plain_text_response(body)
    raise HandshakeError, status unless status == "OK"
  end

  # Yield the the user profile url to a block
  def with_profile_url
    yield "http://www.last.fm/user/#{user}" if user
  end

private
  module DocHelper
    def value_at(xpath)
      REXML::XPath.first(self, xpath).text.strip
    end
  end

  def last_fm_web_service(parameters={})
    xml = get("http://ws.audioscrobbler.com/2.0/",
            signed_parameters(parameters.merge("api_key" => api_key)))
    REXML::Document.new(xml).extend(DocHelper)
  end

  def get(url, parameters)
    query_string = sort_parameters(parameters).
                   map{ |k, v| "#{k}=#{CGI.escape(v)}" }.
                   join("&")
    Net::HTTP.get_response(URI.parse(url + "?" + query_string)).body
  end

  def post(url, parameters)
    Net::HTTP.post_form(URI.parse(url), parameters).body
  end

  def md5(s)
    Digest::MD5.hexdigest(s)
  end

  def signed_parameters(parameters)
    sorted    = sort_parameters(parameters)
    signature = md5(sorted.flatten.join + secret)
    parameters.merge("api_sig" => signature)
  end

  def split_plain_text_response(body)
    body.split(/\n/)
  end

  def sort_parameters(parameters)
    parameters.map{ |k, v| [k.to_s, v.to_s] }.sort
  end

  def generate_scrobbling_parameters(for_scrobble, details)
    mapping = {
      :artist       => "a",
      :track        => "t",
      :length       => "l",
      :album        => "b",
      :track_number => "n",
      :mb_trackid   => "m" }
    if for_scrobble
      mapping.merge!(
        :source => "o",
        :time   => "i",
        :rating => "r" )
      mapping.keys.each do |k|
        mapping[k] << "[0]"
      end
    end
    mapping.inject({"s" => @scrobble_session_id}){ |hash, (key, param)|
      hash[param] = details[key].to_s
      hash
    }
  end

  def enforce_keys(hash, *keys)
    if (extras = hash.keys - keys).any?
      raise DataError, "Unknown hash key(s): #{extras.inspect}"
    end
  end
end
