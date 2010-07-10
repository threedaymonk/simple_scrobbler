SimpleScrobbler
===============

Scrobble tracks to Last.fm without wanting to gnaw your own arm off.

Because, probably, all you want to do is just scrobble some tracks. I couldn't
find any Ruby libraries/gems that actually worked, so I took some code from
James Darling and Chris Mear's [Captor](http://github.com/james/captor) hack
and tidied it up into a self-contained package.

Usage
-----

Authorise.

    require "simple_scrobbler"
    ss = SimpleScrobbler.new(api_key, secret, user)
    ss.fetch_session_key do |url|
      puts "Go and visit #{url}"
      gets
    end

Tell Last.fm what you're listening to.

> This is used for realtime display of a user's currently playing track,
> and does not affect a user's musical profile.

    ss.now_playing("Sex Pistols", "Anarchy in the UK")

Scrobble it!

    ss.submit("Sex Pistols", "Anarchy in the UK", :length => 211)

Store the session_key for next time.

    session_key = ss.session_key

And use it:

    ss = SimpleScrobbler.new(api_key, secret, user, session_key)

You can pass in other information to `submit` and `now_playing`:

* `:time` (for `submit` only): Time at which the track started playing. Defaults to now
* `:length`: Length of the track in seconds (required for `submit` if the source is `P`, the default)
* `:album`: Album title
* `:track_number`: Track number
* `:mb_trackid`: MusicBrainz Track ID

If you're listening to a radio station, [you'll want to set the source](http://www.last.fm/api/submissions):

    ss.source = "R" # Non-personalised broadcast (e.g. Shoutcast, BBC Radio 1).

This will also free you from needing to specify the track length on `submit`.
