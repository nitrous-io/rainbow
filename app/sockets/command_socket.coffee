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

optionsToArgs =
  ignoreCase: '--ignore-case'
  literal: '--literal'

module.exports = class CommandSocket extends RainbowSocket
  namespace: 'command'

  initialize: ->
    this.on 'start',  _.bind(@onStart, this)
    this.on 'search', _.bind(@onSearch,  this)

    @outBuffer = ''
    @errBuffer = ''

  destroy: ->
    @ssh = undefined

  onStart: (boxId, ack) ->
    this.fetchBoxAndKeyPair boxId, (err, box, keyPair) =>
      return ack?(err) if err
      @ssh = new SSHHelper 'action', box.host, box.port, keyPair.private_key
      ack?()

  onSearch: (tabId, term, searchRoot, options, ack) ->
    args = [
      '--ackmate' # for ease of parsing
      '--group' # displays results with file headings
      '--all-text' # search all text files
    ]
    _.each options.split(','), (option) ->
      if arg = optionsToArgs[option]
        args.push(arg)
    args.push(term)
    args.push(searchRoot)
    args = _.map args, this.shellEscape

    this._streamCommand 'search',
      path: searchBinPath,
      args: args
      stdoutFn: (data) =>
        [lineData, @outBuffer] = this.lineBuffer(data, @outBuffer)
        this.sendAs 'search', 'commandOutput', [tabId, lineData].join(IdDataDelimiter)
      stderrFn: (data) =>
        [lineData, @errBuffer] = this.lineBuffer(data, @errBuffer)
        this.sendAs 'search', 'commandError', [tabId, lineData].join(IdDataDelimiter)
      closeFn: (data) =>
        this.sendAs 'search', 'commandComplete', [tabId, data].join(IdDataDelimiter)

    ack?()

  shellEscape: (arg) ->
    arg.replace("\n", "\\n").replace(/([^A-Za-z0-9_\-.,:\/@\n*\?])/g, "\\$1")

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
  # stdoutFn, stderrFn - callbacks with (data) argument that run on command output
  # closeFn - callback with (exitcode) argument that runs on command completion
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
        if command.closeFn
          command.closeFn(code)

      commandProcess.on 'error', ->
        deleteKeyFile()

