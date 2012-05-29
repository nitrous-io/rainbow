pg = require('pg').native

module.exports = class BaseModel
  constructor: (attributes) ->
    this[k] = v for own k, v of attributes

BaseModel.findOne = (condition, values, columns, callback) ->
  if typeof columns == 'function'
    callback = columns
    columns = '*'
  unless this.tableName
    callback(new Error('tableName not defined'), null)
    return
  pg.connect (err, client) =>
    if err
      callback(err, null)
      return
    if columns instanceof Array
      columns.unshift('id') if columns.indexOf('id') == -1
      columns = columns.join(', ')
    client.query "SELECT #{columns} FROM #{@tableName} WHERE #{condition} LIMIT 1", values, (err, res) =>
      if err
        callback(err, null)
        return
      if res && res.rows.length > 0
        model = new this
        model[k] = v for own k, v of res.rows[0]
        callback(null, model)
      else
        callback(null, null)

BaseModel.findById = (id, columns, callback) ->
  if typeof columns == 'function'
    callback = columns
    this.findOne 'id = $1', [id], callback
  else
    this.findOne 'id = $1', [id], columns, callback

