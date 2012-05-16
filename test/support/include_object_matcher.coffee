Assertion = require('should').Assertion
eql = require('should/lib/eql')
i = require('util').inspect

Assertion::includeObject = (obj) ->
  @obj.should.be.a 'object'
  included = true
  for own key, value of obj
    if !eql(value, @obj[key])
      included = false
      break
  this.assert included
            , 'expected ' + @inspect + ' to include ' + i(obj)
            , 'expected ' + @inspect + ' to not include ' + i(obj)
  this

