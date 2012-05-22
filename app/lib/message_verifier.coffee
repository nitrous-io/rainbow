crypto = require 'crypto'

module.exports = class MessageVerifier
  constructor: (secret) ->
    @secret = secret

  verify: (signed) ->
    object = null
    if signed? && signed.length > 4
      [encodedJSON, signature] = signed.split('--')
      mySig = this.signatureFor(encodedJSON)
      if mySig == signature
        try
          json = new Buffer(encodedJSON, 'base64').toString('utf8')
          object = JSON.parse(json)
        catch err
          object = null
    object

  generate: (object) ->
    json = JSON.stringify(object)
    encodedJSON = new Buffer(json, 'utf8').toString('base64')
    signature = this.signatureFor(encodedJSON)
    "#{encodedJSON}--#{signature}"

  signatureFor: (string) ->
    crypto.createHmac('sha1', @secret).update(string).digest('hex')

