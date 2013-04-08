actionBase = require 'action-base'
BaseModel = actionBase.BaseModel
actionCipher = actionBase.actionCipher
app = require '../../app'

module.exports = class KeyPair extends BaseModel
  @tableName: 'key_pairs'

KeyPair::__defineGetter__ 'private_key', ->
  actionCipher.decrypt app.settings.aesKey, @encrypted_private_key_iv, @encrypted_private_key

