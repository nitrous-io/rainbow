_ = require 'underscore'
actionBase = require 'action-base'
BaseSocket = actionBase.BaseSocket
Box = require '../models/box'

module.exports = class RainbowSocket extends BaseSocket
  namespace: 'rainbow'

  initialize: ->

  destroy: ->

  fetchBoxAndKeyPair: (boxId, ack) ->
    return unless @connection && @connection.isAuthenticated()
    Box.findById boxId, ['owner_id', 'host', 'port'], (err, box) =>
      return ack?('failed to fetch box') if err
      return ack?('box not found') unless box
      box.isAccessibleByUserId @connection.userId, (err, accessible) =>
        return ack?('unable to verify access permission') if err
        return ack?("box doesn't belong to user") unless accessible
        box.findKeyPair (err, keyPair) =>
          return ack?('failed to fetch key pair') if err
          return ack?('key pair not found') unless keyPair
          ack? null, box, keyPair
