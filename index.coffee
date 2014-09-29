config = require './config.coffee'

r = require 'rethinkdb'
rdbConn =
r.connect config.rethinkdb, (err, conn) ->
  if err?
    console.log "RethinkDB Error: #{err}"
    process.exit 1
  else
    rdbConn = conn

  db = config.rethinkdb.db
  r.db(db).tableCreate('karma').run rdbConn, (err, result) ->
    throw err if err? and err.name isnt 'RqlRuntimeError'

  Slack = require 'node-slack'
  slack = new Slack(config.slack.domain, config.slack.token)
  
  express = require 'express'
  app = express()
  bodyParser = require 'body-parser'
  app.use bodyParser.urlencoded extended: true
  app.use bodyParser.json()
  
  router = express.Router()
  
  router.post '/hubot/slack-webhook', (req, res) ->
    params = ['channel_name', 'user_name', 'text']
    for param in params
      continue if not req.body[param]

    regex = /^(.+)(\+\+|\-\-)( for (.*))?$/
    from = req.body.user_name.toLowerCase()
    if regex.test req.body.text
      params = req.body.text.match regex
      to = params[1].toLowerCase()
      type = params[2]
      reason = if params[4] isnt undefined then params[4] else null

      r.table('karma').insert({
        from: from
        to: to
        reason: reason
        type: type
      }).run rdbConn, (err, result) ->
        if err
          slack.send {
            text: "Error: #{err}"
            channel: "##{req.body.channel_name}"
            username: 'WGACA'
          }
        else
          r.table('karma').filter(r.row('to').eq(to)).filter(r.row('type').eq('++')).count().run rdbConn, (err, increaseCount) ->
            if err
              slack.send {
                text: "Error: #{err}"
                channel: "##{req.body.channel_name}"
                username: 'WGACA'
              }
            else
              r.table('karma').filter(r.row('to').eq(to)).filter(r.row('type').eq('--')).count().run rdbConn, (err, decreaseCount) ->
                if err
                  slack.send {
                      text: "Error: #{err}"
                      channel: "##{req.body.channel_name}"
                      username: 'WGACA'
                    }
                else
                  points = increaseCount - decreaseCount
                  text = "#{to} == #{points}"
                  if reason
                    text += " for #{reason}"
                  slack.send {
                    text: text
                    channel: "##{req.body.channel_name}"
                    username: 'WGACA'
                  }
  
  app.use router
  
  app.listen config.express.port, config.express.host, ->
    console.log "Express listening on #{config.express.host}:#{config.express.port}"