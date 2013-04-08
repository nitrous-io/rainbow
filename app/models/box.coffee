_ = require 'underscore'
BaseModel = require('action-base').BaseModel
KeyPair = require './key_pair'
BoxUser = require './box_user'

module.exports = class Box extends BaseModel
  @tableName: 'boxes'

  findKeyPair: (callback) -> # callback(err, model)
    KeyPair.findOne 'box_id = $1', [@id], callback

  findUserIds: (callback) -> # callback(err, userIds:Array)
    BoxUser.findMany 'box_id = $1', [@id], ['user_id'], (err, models) ->
      return callback(err) if err
      userIds = _.chain(models).pluck('user_id').unshift(42).uniq().compact().value()
      callback null, userIds

  isAccessibleByUserId: (userId, callback) -> # callback(err, isAccessible:Boolean)
    if userId == @owner_id
      return callback null, true
    this.findUserIds (err, userIds) ->
      return callback(err) if err
      callback null, userIds.indexOf(userId) != -1
