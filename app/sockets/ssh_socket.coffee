process.env.TERM = 'xterm-256color'

_ = require 'underscore'
actionBase = require 'action-base'
BaseSocket = actionBase.BaseSocket
SSHHelper = actionBase.SSHHelper
Box = require '../models/box'
pty = require 'pty.js'

module.exports = class SSHSocket extends BaseSocket
  namespace: 'ssh'

  initialize: ->
    this.on 'start', _.bind(@onStart,  this)
    this.on 'd',     _.bind(@onData,   this)
    this.on 'r',     _.bind(@onResize, this)
    this.on 'kill',  _.bind(@onKill,   this)
    @sshStarted = false

  destroy: ->
    @sshStarted = false
    @pty?.removeAllListeners()
    @pty?.destroy()
    @pty = undefined
    @box = undefined

  onStart: (boxId, ack) ->
    @sshStarted = false
    Box.findById boxId, ['owner_id', 'host', 'port'], (err, box) =>
      return unless @connection && @connection.isAuthenticated()
      return ack?('failed to fetch box') if err
      return ack?('box not found') unless box
      box.isAccessibleByUserId @connection.userId, (err, accessible) =>
        return ack?('unable to verify access permission') if err
        return ack?("box doesn't belong to user") unless accessible
        return ack?('pty already created') if @pty
        @box = box
        this.connectToSSH (err) =>
          return ack?('failed to create ssh connection') if err
          ack?()

  onData: (data) ->
    @pty?.write data.toString() if @sshStarted

  onResize: (width, height) ->
    try
      @pty?.resize width, height
    catch err
      console.log err
      console.log err.message
      console.log err.stack
      @destroy()

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
        @pty.once 'data', =>
          deleteKeyFile()
          @sshStarted = true
        @pty.on 'data',  _.bind(@onPTYData, this)
        @pty.on 'close', _.bind(@onPTYClose, this)
        callback null

  onPTYData: (data) ->
    this.send 'p', data

  onPTYClose: (hadError) ->
    this.send 'close'
    this.destroy()

