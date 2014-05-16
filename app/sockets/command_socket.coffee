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

SearchCommand = require '../../app/commands/search_command'

module.exports = class CommandSocket extends RainbowSocket
  namespace: 'command'

  initialize: ->
    this.on 'start',  _.bind(@onStart, this)
    this.on 'search', _.bind(@onSearch,  this)

  destroy: ->
    @ssh = undefined

  onStart: (boxId, ack) ->
    this.fetchBoxAndKeyPair boxId, (err, box, keyPair) =>
      return ack?(err) if err
      @ssh = new SSHHelper 'action', box.host, box.port, keyPair.private_key
      ack?()

  onSearch: (tabId, term, searchRoot, options, ack) ->
    cmd = new SearchCommand term, searchRoot, options, (event, data) =>
      this.sendAs 'search', event, [tabId, data].join(SearchCommand.idDataDelimiter)

    this._streamCommand 'search', cmd.makeCommand()

    ack?()

  send: (event, args...) ->
    throw "Cannot use send in CommandSocket, use sendAs"

  sendAs: (namespace, event, args...) ->
    @connection.send [namespace, event, args]

  # the command for _streamCommand is an object with the following keys:
  # path - string, path of command
  # args - array, arguments to command
  # stdoutFn, stderrFn - callbacks with (data, process) arguments that run on command output
  # closeFn - callback with (exitcode) argument that runs on command completion
  # errorFn - callback with no arguments that runs on errors
  _streamCommand: (namespace, command) ->
    @ssh.writeKeyFile (err, sshArgs, deleteKeyFile) =>
      if err
        return

      sshArgs.push "--"
      sshArgs.push "LC_ALL=en_US.UTF-8"
      sshArgs.push "#{command.path} #{command.args.join(' ')}"

      commandProcess = childProcess.spawn '/usr/bin/ssh', sshArgs, { env: {} }

      commandProcess.stdout.on 'data', (data) =>
        if command.stdoutFn
          command.stdoutFn(data, commandProcess)

      commandProcess.stderr.on 'data', (data) =>
        if command.stderrFn
          command.stderrFn(data, commandProcess)

      commandProcess.on 'close', (code) =>
        if command.closeFn
          command.closeFn(code)
        deleteKeyFile()

      commandProcess.on 'error', ->
        if command.errorFn
          command.errorFn()
        deleteKeyFile()
