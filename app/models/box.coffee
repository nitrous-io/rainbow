BaseModel = require('action-base').BaseModel
BoxAdmin  = require '../../app/models/box_admin'
KeyPair   = require './key_pair'
A         = require 'async'

module.exports = class Box extends BaseModel
  findKeyPair: (callback) ->
    KeyPair.findOne 'box_id = $1', [@id], callback

# find a box that user can worked on. The box can be created by the user, or
# shared to the user, in which ever cases user should belongs to `box_admins`
Box.forUser = (boxId, userId, callback) ->
  A.waterfall [
    (cb) -> BoxAdmin.isAllowed boxId, userId, cb
    (isAllowed, cb) -> Box.findOne "id = $1", [boxId], 'id, owner_id, host, port', cb
  ], (err, res) ->
    return callback err if err
    return callback "box not found" unless res
    callback null, res

Box.tableName = 'boxes'

