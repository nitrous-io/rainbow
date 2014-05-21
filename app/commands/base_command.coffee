# BaseCommand class
# * provides line limiting and buffers so that newline-terminated lines are
#   sent
# * inheriting classes must implement commandPath() and commandArguments()
#   for basic functionality
# * inheriting classes may override detectErrors(stderrData) for
#   specialized error-handling

module.exports = class BaseCommand
  resultLimit: 500

  constructor: ->
    @outBuffer = ''
    @errBuffer = ''
    @lineCount = 0
    @stopStdout = false

  makeCommand: ->
    return (
      sshCommand: [this.commandPath()].concat(this.commandArguments()).join(' ')
      stdoutFn: this.stdoutFn
      stderrFn: this.stderrFn
      closeFn: this.closeFn
    )

  commandPath: ->
    throw "Not implemented"

  commandArguments: ->
    throw "Not implemented"

  stdoutFn: (data, cprocess) =>
    return if @stopStdout
    [data, updatedLineCount] = this._limitLines(data, @lineCount)
    [data, @outBuffer] = this._lineBuffer(data, @outBuffer)
    this.sendFn 'commandOutput', data
    if updatedLineCount == -1
      @stopStdout = true
      this.sendFn 'commandError', this.errorSlugs.limit
      cprocess.kill() # will trigger 'close' event
    else
      @lineCount = updatedLineCount

  stderrFn: (data, cprocess) =>
    @errBuffer += data

  closeFn: (data) =>
    this._handleErrors @errBuffer, (errSlug) =>
      this.sendFn 'commandError', errSlug
    this.sendFn 'commandComplete', data

  detectErrors: (data) ->
    null

  _handleErrors: (data, callback) ->
    return if data == ''
    data = data.replace(/\n/g, "\\n")
    if errorSlug = this.detectErrors(data)
      callback(errorSlug)
    else
      console.log("Unhandled #{this.commandPath()} error: #{data}")

  # ensures that output sent over websocket terminates with newline
  _lineBuffer: (data, bufferVal) ->
    lineData = (bufferVal || '') + data
    if lineData.slice(-1) != "\n"
      lastNewlinePos = lineData.lastIndexOf("\n")
      bufferVal = lineData.slice(lastNewlinePos + 1)
      lineData = lineData.slice(0, lastNewlinePos + 1)
    else
      bufferVal = ''
    return [lineData, bufferVal]

  _shellEscape: (arg) ->
    arg.replace("\n", "\\n").replace(/([^A-Za-z0-9_\-.,:\/@\n*\?])/g, "\\$1")

  # Arguments
  # * data - from childProcess stdout
  # * currentCount - current number of lines seen
  # returns
  # * truncatedData - lines to send back
  # * newCount - updated count of lines seen (-1 if exceeded)
  _limitLines: (data, currentCount) ->
    if currentCount == this.resultLimit
      return ['', -1]
    lines = data.split("\n")
    updatedLineCount = currentCount + lines.length - 1
    if updatedLineCount > this.resultLimit
      [lines.slice(0, this.resultLimit - currentCount).join("\n") + "\n", -1]
    else
      [data, updatedLineCount]
