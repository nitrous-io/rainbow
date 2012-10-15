_ = require 'underscore'
BaseSocket = require './base_socket'
Box = require '../models/box'
SSHHelper = require('action-base').SSHHelper
pty = require 'pty.js'

module.exports = class SSHSocket extends BaseSocket
  @EVENTS: ['start', 'd', 'r', 'kill']

  onStart: (boxId) ->
    Box.findById boxId, ['owner_id', 'host', 'port'], (err, box) =>
      if err
        @socket.emit 'start', err.toString()
        return
      unless box
        @socket.emit 'start', 'box not found'
        return
      if box.owner_id != @user.id
        @socket.emit 'start', "box doesn't belong to user"
        return
      if @pty
        @socket.emit 'start', 'pty already created'
        return
      @box = box
      this.connectToSSH (err) =>
        if err
          @socket.emit 'start', err.toString()
          return
        @socket.emit 'start'

  onD: (data) ->
    @pty?.write data

  onR: (width, height) ->
    @pty?.resize width, height

  onKill: ->
    @socket.disconnect()
    this.destroy()

  connectToSSH: (callback) ->
    @box?.findKeyPair (err, keyPair) =>
      if err
        callback err
        return
      unless keyPair
        callback 'key pair not found'
        return

      sshHelper = new SSHHelper('action', @box.host, @box.port, keyPair.private_key)
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
    @socket?.emit 'd', data

  onPTYClose: (hadError) ->
    delete @pty
    @socket?.emit 'close'

