BaseModel = require('action-base').BaseModel
_ = require 'underscore'
A = require 'async'

module.exports = class BoxAdmin extends BaseModel
  @tableName: 'box_admins'
  @isAllowed: (boxId, userId, callback) ->
    BoxAdmin.findOne 'box_id = $1 AND user_id = $2', [boxId, userId], (err, box) ->
      return callback err, false if err
      isAllowed = !_.isEmpty box
      msg = if isAllowed then null else "not allowed to access this box"
      callback msg, isAllowed
