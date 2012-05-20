pg = require('pg').native

module.exports = class BaseModel

BaseModel.findById = (id, callback) ->
  unless this.tableName
    callback(new Error('tableName not defined'), null)
    return
  pg.connect (err, client) =>
    if err
      callback(err, null)
      return
    client.query "SELECT * FROM #{@tableName} WHERE id = $1", [id], (err, res) =>
      if err
        callback(err, null)
        return
      if res && res.rows.length > 0
        model = new this
        model[k] = v for k, v of res.rows[0]
        callback(null, model)
      else
        callback(null, null)

