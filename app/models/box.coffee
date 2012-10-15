BaseModel = require('action-base').BaseModel
KeyPair = require './key_pair'

module.exports = class Box extends BaseModel
  findKeyPair: (callback) ->
    KeyPair.findOne 'box_id = $1', [@id], callback

Box.tableName = 'boxes'

