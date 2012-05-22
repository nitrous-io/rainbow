BaseModel = require './base_model'
MessageVerifier = require '../lib/message_verifier'
settings = require '../../config/settings'

module.exports = class User extends BaseModel
  passwordSalt: ->
    @encrypted_password?.substring(0,29) || null

User.tableName = 'users'

User.verifyUserSession = (session, callback) ->
  verifier = new MessageVerifier(settings.secretToken)
  message = verifier.verify(session)
  unless message
    callback(null, null)
    return
  userId = message['warden.user.user.key']?[1]?[0]
  salt = message['warden.user.user.key']?[2]
  unless userId && salt
    callback(null, null)
    return
  User.findById userId, (err, user) ->
    unless user && user.passwordSalt() == salt
      callback(err, null)
      return
    callback(null, user)

