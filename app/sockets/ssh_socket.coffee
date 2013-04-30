process.env.TERM = 'xterm-256color'

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

