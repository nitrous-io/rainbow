decodeURLSafeBase64 = (string) ->
  string = string.replace(/-/g,'+').replace(/_/g, '/')
  new Buffer(string, 'base64').toString('utf8')

module.exports = class AuthTokenVerifier
  constructor: (@name, @messageVerifier) ->

  verify: (token) ->
    if verifiedToken = @messageVerifier.verify decodeURLSafeBase64(token)
      [userId, name, expiresAt] = verifiedToken
      now = Math.floor(+new Date / 1000)
      if (name == @name) && (expiresAt > now)
        return userId
    null

