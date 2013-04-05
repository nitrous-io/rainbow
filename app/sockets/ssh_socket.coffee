_ = require 'underscore'
BaseSocket = require './base_socket'
Box = require '../models/box'
SSHHelper = require('action-base').SSHHelper
pty = require 'pty.js'

module.exports = class SSHSocket extends BaseSocket
  namespace: 'ssh'

  initialize: ->
    this.on 'start', _.bind(@onStart,  this)
    this.on 'd',     _.bind(@onData,   this)
    this.on 'r',     _.bind(@onResize, this)
    this.on 'kill',  _.bind(@onKill,   this)

  destroy: ->
    @pty?.destroy()
    @pty = null
    @box = null

  onStart: (boxId, ack) ->
    Box.findById boxId, ['owner_id', 'host', 'port'], (err, box) =>
      return unless @connection && @connection.isAuthenticated()
      if err
        ack? err.toString()
        return
      unless box
        ack? 'box not found'
        return
      if box.owner_id != @connection.userId
        ack? "box doesn't belong to user"
        return
      if @pty
        ack? 'pty already created'
        return
      @box = box
      this.connectToSSH (err) =>
        if err
          ack? err.toString()
          return
        ack?()

  onData: (data) ->
    @pty?.write data

  onResize: (width, height) ->
    @pty?.resize width, height

  onKill: ->
    this.destroy()

  connectToSSH: (callback) ->
    @box?.findKeyPair (err, keyPair) =>
      return unless @box

      if err
        callback err
        return
      unless keyPair
        callback 'key pair not found'
        return

      sshHelper = new SSHHelper 'action', @box.host, @box.port, keyPair.private_key
      sshHelper.writeKeyFile (err, sshArgs, deleteKeyFile) =>
        if err
          callback err
          return
        try
          @pty = pty.spawn '/usr/bin/ssh', sshArgs
        catch err
          deleteKeyFile ->
            callback err
          return
        @pty.once 'data', ->
          deleteKeyFile()
        @pty.on 'data',  _.bind(@onPTYData, this)
        @pty.on 'close', _.bind(@onPTYClose, this)
        callback null

  onPTYData: (data) ->
    this.send 'p', data

  onPTYClose: (hadError) ->
    this.send 'close'
    this.destroy()

