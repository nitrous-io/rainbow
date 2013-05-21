BaseModel = require('action-base').BaseModel
settings = require '../../config/settings'
app = require '../../app'

module.exports = class User extends BaseModel
  passwordSalt: ->
    @encrypted_password?.substring(0,29) || null

User.tableName = 'users'

User.verifyUserSession = (session, callback) ->
  verifier = app.messageVerifier
  message = verifier.verify(session)
  unless message
    callback(null, null)
    return
  userId = message['warden.user.user.key']?[0]?[0]
  salt = message['warden.user.user.key']?[1]
  unless userId && salt
    callback(null, null)
    return
  User.findById userId, (err, user) ->
    unless user && user.passwordSalt() == salt
      callback(err, null)
      return
    callback(null, user)

