_ = require 'underscore'

BaseCommand = require './base_command'

matcherPath="/usr/local/bin/matcher"

module.exports = class FileFindCommand extends BaseCommand
  # multiple searches can be in-flight simultaneously, so we need to tag data
  # sent over the socket with the search it corresponds to.  This is the
  # separator used -- id is guaranteed numeric
  @idDataDelimiter = "!!\n"

  # separator between file pattern and path so that (pattern1, path1) and
  # (pattern2, path2) do not overlap
  @searchKeyDelimiter = "\\\\"

  resultLimit: 10 # matcher will return 10 by default

  errorSlugs:
    pathNotFound: 'NOPATH'
    noBinary: 'NOBINARY'

  # @term - search term
  # @location - search location, e.g. workspace or workspace/*.py
  # @sendFn - func(event, data) to be called for sending over socket
  constructor: (@term, @location, @sendFn) ->
    super()
    @term = this._shellEscape(@term)

  makeCommand: ->
    cmd = super()
    cmd.sshCommand = "sh -c '#{cmd.sshCommand} | #{matcherPath} #{@term}'"
    cmd

  commandPath: ->
    '/usr/local/bin/ag'

  commandArguments: ->
    args = [
      '-i' # this must come before -g as ag case-sensitivity arguments are positionally aware
      '-g'
    ]
    args.push(this.regexTerm(@term))
    args.push(@location)
    _.map args, this._shellEscape

  regexTerm: (term) ->
    parts = _.map term.split(''), (letter) ->
      ".*?#{letter}"
    parts.join('') + '.*?'

  detectErrors: (data) ->
    switch
      when data.match /Error stat\(\)ing/
        this.errorSlugs.pathNotFound
      when data.match /matcher: not found/
        this.errorSlugs.noBinary
      else
        null
