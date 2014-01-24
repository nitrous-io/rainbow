process.env.TERM = 'xterm-256color'

_ = require 'underscore'
actionBase = require 'action-base'
RainbowSocket = require './rainbow_socket'
SSHHelper = actionBase.SSHHelper
pty = require 'pty.js'

module.exports = class TmuxSocket extends RainbowSocket
  namespace: 'tmux'

  initialize: ->
    this.on 'start',          _.bind(@onStart,          this)
    this.on 'createSession',  _.bind(@onCreateSession,  this)
    this.on 'createWindow',   _.bind(@onCreateWindow,   this)
    this.on 'selectWindow',   _.bind(@onSelectWindow,   this)
    this.on 'removeWindow',   _.bind(@onRemoveWindow,  this)
    #this.on 'renameWindow',    _.bind(@onRenameWindow,    this)
    @sshStarted = false
    @sessionId = null

  destroy: ->
    @pty?.write "tmux kill-session -t #{@sessionId}\n"
    process.nextTick =>
      @sshStarted = false
      @sessionId = null
      @pty?.removeAllListeners()
      @pty?.destroy()
      @pty = undefined

  onStart: (boxId, ack) ->
    @sshStarted = false
    return ack?('pty already created') if @pty
    this.fetchBoxAndKeyPair boxId, (err, box, keyPair) =>
      return ack?(err) if err
      this.connectToSSH box, keyPair, (error) =>
        return ack?('failed to create ssh connection') if error
        ack?()

  connectToSSH: (box, keyPair, callback) ->
    sshHelper = new SSHHelper 'action', box.host, box.port, keyPair.private_key
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

  onCreateSession: (ack) ->
    @sessionId = +new Date()
    @pty?.write "tmux new-session -d -s #{@sessionId}\n"
    ack? null, @sessionId

  onCreateWindow: (windowId) ->
    @pty?.write "tmux new-window -t #{@sessionId}:#{windowId}\n"

  onSelectWindow: (windowId) ->
    @pty?.write "tmux select-window -t #{@sessionId}:#{windowId}\n"

  onRemoveWindow: (windowId) ->
    @pty?.write "tmux kill-window -t #{@sessionId}:#{windowId}\n"

  onPTYData: (data) ->
    #this.send 'p', data

  onPTYClose: (hadError) ->
    this.destroy()
