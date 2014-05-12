# Unlike existing sockets, a CommandSocket supports multiple namespaces.
# Shares a lot of functionality with PartsSocket.  PartsSocket functionality
# should eventually be moved here.

_ = require 'underscore'
actionBase = require 'action-base'
RainbowSocket = require './rainbow_socket'
SSHHelper = actionBase.SSHHelper
stringHelper = actionBase.stringHelper
app = require '../../app'

childProcess = require 'child_process'

homePath = '/home/action'
searchBinPath = "/usr/bin/ag"

IdDataDelimiter = "!!\n"

module.exports = class CommandSocket extends RainbowSocket
  namespace: 'command'

  initialize: ->
    this.on 'start',  _.bind(@onStart, this)
    this.on 'search', _.bind(@search,  this)

    @outBuffer = ''
    @errBuffer = ''

  destroy: ->
    @ssh = undefined

  onStart: (boxId, ack) ->
    this.fetchBoxAndKeyPair boxId, (err, box, keyPair) =>
      return ack?(err) if err
      @ssh = new SSHHelper 'action', box.host, box.port, keyPair.private_key
      ack?()

  search: (tabId, term, searchRoot, ack) ->
    console.log "Got term #{term}, search root #{searchRoot}, ack #{ack}"
    # --search-files is an undocumented option -- it forces the grouping of
    # files despite stdin being a pipe (default for childProcess.spawn)
    #
    # FIXME: we need to specify colors since we're matching on them so that if
    # user has a local .agrc file we don't match on the wrong colors
    this._streamCommand 'search',
      path: searchBinPath,
      args: ["--group", "--color", "--search-files", term, searchRoot]
      stdoutFn: (data) =>
        [lineData, @outBuffer] = this.lineBuffer(data, @outBuffer)
        this.sendAs 'search', 'commandOutput', [tabId, lineData].join(IdDataDelimiter)
      stderrFn: (data) =>
        [lineData, @errBuffer] = this.lineBuffer(data, @errBuffer)
        this.sendAs 'search', 'commandError', [tabId, lineData].join(IdDataDelimiter)
    ack?()

  # ensures that output sent over websocket terminates with newline
  lineBuffer: (data, bufferVal) ->
    lineData = bufferVal + data.toString()
    if lineData.slice(-1) != "\n"
      lastNewlinePos = lineData.lastIndexOf("\n")
      bufferVal = lineData.slice(lastNewlinePos + 1)
      lineData = lineData.slice(0, lastNewlinePos + 1)
    else
      bufferVal = ''
    return [lineData, bufferVal]

  send: (event, args...) ->
    throw "Cannot use send in CommandSocket, use sendAs"

  sendAs: (namespace, event, args...) ->
    @connection.send [namespace, event, args]

  # the command for _streamCommand is an object with the following keys:
  # path - string, path of command
  # args - array, arguments to command
  # stdoutFn, stderrFn - callbacks with (data) argument that run on 
  _streamCommand: (namespace, command) ->
    @ssh.writeKeyFile (err, sshArgs, deleteKeyFile) =>
      if err
        return

      sshArgs.push "--"
      sshArgs.push "LC_ALL=en_US.UTF-8"
      sshArgs.push "#{command.path} #{command.args.join(' ')}"

      lineCount = 0

      commandProcess = childProcess.spawn '/usr/bin/ssh', sshArgs, { env: {} }

      commandProcess.stdout.on 'data', command.stdoutFn
      commandProcess.stderr.on 'data', command.stderrFn

      commandProcess.on 'close', (code) =>
        deleteKeyFile()
        this.sendAs namespace, 'commandComplete', code

      commandProcess.on 'error', ->
        deleteKeyFile()

