process.env.TERM = 'xterm-256color'

_ = require 'underscore'
actionBase = require 'action-base'
RainbowSocket = require './rainbow_socket'
SSHHelper = actionBase.SSHHelper
pty = require 'pty.js'

module.exports = class SSHSocket extends RainbowSocket
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

  onStart: (boxId, sessionToken, ack) ->
    @sshStarted = false
    return ack?('pty already created') if @pty
    this.fetchBoxAndKeyPair boxId, (err, box, keyPair) =>
      return ack?(err) if err
      this.connectToSSH box, keyPair, sessionToken, (error) =>
        return ack?('failed to create ssh connection') if error
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

  connectToSSH: (box, keyPair, sessionToken, callback) ->
    sshHelper = new SSHHelper 'action', box.host, box.port, keyPair.private_key
    sshHelper.writeKeyFile (err, sshArgs, deleteKeyFile) =>
      if err
        callback err
        return
      try
        # Since SendEnv option for SSH is not enabled, going with this hack,
        # of setting LC_* env variable. which are passed to the remote server.
        @pty = pty.spawn "/usr/bin/ssh", sshArgs, { env: { LC_SESSION_TOKEN: sessionToken } }
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

