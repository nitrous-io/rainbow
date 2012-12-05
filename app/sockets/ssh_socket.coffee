_ = require 'underscore'
BaseSocket = require './base_socket'
Box = require '../models/box'
SSHHelper = require('action-base').SSHHelper
pty = require 'pty.js'
A = require 'async'

module.exports = class SSHSocket extends BaseSocket
  @EVENTS: ['start', 'd', 'r', 'kill']

  onStart: (boxId, ack) ->
    A.waterfall [
      (cb) => Box.forUser boxId, @user.id, cb
      (@box, cb) => @connectToSSH cb
    ], (err) -> ack? err?.toString()

  onD: (data) ->
    @pty?.write data

  onR: (width, height) ->
    @pty?.resize width, height

  onKill: ->
    @socket.disconnect()
    this.destroy()

  connectToSSH: (callback) ->
    return callback("pty already created") if @pty
    @box?.findKeyPair (err, keyPair) =>
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

  destroy: ->
    super()
    @pty?.destroy()
    delete @pty
    delete @box

  onPTYData: (data) ->
    @socket?.emit 'p', data

  onPTYClose: (hadError) ->
    delete @pty
    @socket?.emit 'close'

