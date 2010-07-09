require 'net/http'
require 'digest/md5'
require 'uri'

class SimpleScrobbler
  def initialize(api_key, secret, user, auth_key=nil)
    @api_key    = api_key
    @secret     = secret
    @user       = user
    @auth_key   = auth_key
    @source     = "P"
    @handshaken = false
  end

  # The source of the track. Required, must be one of the following codes:
  # P :: Chosen by the user.
  # R :: Non-personalised broadcast (e.g. Shoutcast, BBC Radio 1).
  # E :: Personalised recommendation except Last.fm (e.g. Pandora, Launchcast).
  # L :: Last.fm (any mode).
  #
  def source=(a)
    unless %w[ P R E L ].include?(a)
      raise "source must be one of P, R, E, L (see http://www.last.fm/api/submissions)"
    end
    @source = a
  end

  # Fetch the auth key needed for the application. This can be stored and
  # supplied in the constructor on future occasions.
  #
  # Yields a URL which the user must visit. The block should not return until
  # this is done.
  #
  def fetch_auth_key(&blk)
    request_token = get_xml_tag("token", call_last_fm("method" => "auth.gettoken"))

    yield "http://www.last.fm/api/auth?api_key=#{@api_key}&token=#{request_token}"

    response = call_last_fm("method" => "auth.getsession", "token" => request_token)

    @auth_key = get_xml_tag('key',  response)
    @user     = get_xml_tag('name', response)

    @auth_key
  end

  #
  #
  #
  def submit(artist, title)
    handshake
    response = Net::HTTP.post_form(URI.parse(@submission_url), {
      's' => @scrobble_session_id,
      'a[0]' => artist,
      't[0]' => title,
      'i[0]' => Time.now.utc.to_i.to_s,
      'o[0]' => @source,
      'r[0]' => '',
      'l[0]' => '',
      'b[0]' => '',
      'n[0]' => '',
      'm[0]' => ''
    })
    response.body
  end

private
  def call_last_fm(parameters={})
    parameters["api_key"] = @api_key
    ordered_parameters = parameters.keys.sort
    concatenated_parameters =
      ordered_parameters.inject(""){ |memo, p|
        memo + p.to_s + parameters[p]
      }
    parameters['api_sig'] = Digest::MD5.hexdigest(concatenated_parameters + @secret)

    url_parameters = parameters.map{ |k,v| "#{k}=#{v}"}.join("&")

    response = Net::HTTP.get_response('ws.audioscrobbler.com', "/2.0/?#{url_parameters}")
    response.body
  end

  def get_xml_tag(tagname, body)
    r = Regexp.new("<#{tagname}>(.+)<\/#{tagname}>")
    body.match(r)[1]
  end

  def handshake
    return if @handshaken
    timestamp = Time.now.utc.to_i.to_s
    authentication_token = Digest::MD5.hexdigest(@secret + timestamp)
    querystring = "/?hs=true&p=1.2.1&c=tst&v=1.0&u=#{username}&t=#{timestamp}&a=#{authentication_token}&api_key=#{@api_key}&sk=#{key}"
    response = Net::HTTP.get_response('post.audioscrobbler.com', querystring)
    responses = response.body.split("\n")
    @scrobble_session_id = responses[1]
    @submission_url      = responses[3]
    @handshaken = true
  end
end
