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
FileFindCommand = require '../../app/commands/file_find_command'

# The ControlPath option of ssh is set to this value, which is the file used by
# ssh to persist the connection.
#   %r will be replaced by remote user name
#   %h will be replaced by target host name
#   %p will be replaced by destination port
# This way each unique connection has its own file
# `man 5 ssh_config` for more details
controlPath = '/tmp/sshconn-%r-%h-%p'

module.exports = class CommandSocket extends RainbowSocket
  namespace: 'command'

  initialize: ->
    this.on 'start',  _.bind(@onStart, this)
    this.on 'search', _.bind(@onSearch,  this)
    this.on 'filefind', _.bind(@onFileFind,  this)

  destroy: ->
    # if the socket is set up but no commands are ever issued,
    # there won't be an ssh connection to terminate
    if !@sshConnected
      @ssh = undefined
      return

    return if !@ssh

    @ssh.writeKeyFile (err, sshArgs, deleteKeyFile) =>
      if err
        return

      sshArgs = this._addSshOptions sshArgs, [
        "-o ControlPath=#{controlPath}"
        '-O exit' # instruct the ControlMaster to exit
      ]

      childProcess.exec "/usr/bin/ssh #{sshArgs.join(' ')}", (err) ->
        if err != null
          console.log("ERR: Error exiting ssh connection: #{err} #{sshArgs}")
        deleteKeyFile()

        @ssh = undefined
        @sshConnected = false

  onStart: (boxId, ack) ->
    this.fetchBoxAndKeyPair boxId, (err, box, keyPair) =>
      return ack?(err) if err

      @ssh = new SSHHelper 'action', box.host, box.port, keyPair.private_key
      @ssh.writeKeyFile (err, sshArgs, deleteKeyFile) =>
        return ack?(err) if err
        return ack?() if @sshConnected

        sshArgs = this._addSshOptions sshArgs, [
          # ControlMaster=yes : create a master connection on socket at
          # location given in ControlPath
          # ControlPersist=yes : keep master connection around indefinitely until
          # issued ssh command with `-O exit`
          "-o ControlPath=#{controlPath}"
          '-o ControlMaster=yes'
          '-o ControlPersist=yes'
        ]
        sshArgs.push "--"
        sshArgs.push "LC_ALL=en_US.UTF-8"
        sshArgs.push '/bin/echo' # dummy command

        masterProcess = childProcess.spawn '/usr/bin/ssh', sshArgs, { env: {} }

        masterProcess.on 'error', =>
          @sshConnected = false

        deleteKeyFile()
        ack?()

  onSearch: (tabId, term, searchRoot, options, ack) ->
    cmd = new SearchCommand term, searchRoot, options, (event, data) =>
      this.sendAs 'search', event, [tabId, data].join(SearchCommand.idDataDelimiter)

    this._streamCommand 'search', cmd.makeCommand(), ack

  onFileFind: (term, location, ack) ->
    cmd = new FileFindCommand term, location, (event, data) =>
      id = [term, location].join(FileFindCommand.searchKeyDelimiter)
      this.sendAs 'filefind', event, [id, data].join(FileFindCommand.idDataDelimiter)

    this._streamCommand 'filefind', cmd.makeCommand(), ack

  send: (event, args...) ->
    throw "Cannot use send in CommandSocket, use sendAs"

  sendAs: (namespace, event, args...) ->
    @connection.send [namespace, event, args]

  # the command for _streamCommand is a child of BaseCommand
  _streamCommand: (namespace, command, ack) ->
    if !@ssh
      console.log("WARN: Received #{namespace} with no ssh connection")
      ack?('No ssh connection')
      return

    @ssh.writeKeyFile (err, sshArgs, deleteKeyFile) =>
      return ack?(err) if err

      sshArgs = this._addSshOptions sshArgs, [
        # ControlMaster=no : attempt to use master connection, fall back to
        # creating a new one if it doesn't already exist
        '-o ControlMaster=no'
        "-o ControlPath=#{controlPath}"
      ]
      sshArgs.push "--"
      sshArgs.push "LC_ALL=en_US.UTF-8"
      sshArgs.push command.sshCommand

      commandProcess = childProcess.spawn '/usr/bin/ssh', sshArgs, { env: {} }

      commandProcess.stdout.on 'data', (data) ->
        command.stdoutFn?(data.toString(), commandProcess)

      commandProcess.stderr.on 'data', (data) ->
        command.stderrFn?(data.toString(), commandProcess)

      commandProcess.on 'close', (code) ->
        command.closeFn?(code)
        deleteKeyFile()

      commandProcess.on 'error', ->
        command.errorFn?()
        deleteKeyFile()

      ack?()

  _addSshOptions: (sshArgs, options) ->
    # last element of sshArgs from writeKeyFile callback is user@host
    sshArgs.slice(0, -1).concat(options).concat(sshArgs.slice(-1))

