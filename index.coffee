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

    regex = /^([^\s]+?)([\+]{2,}|[\-]{2,})((?: for)? (.*))?$/
    from = req.body.user_name.toLowerCase()
    if regex.test req.body.text
      params = req.body.text.match regex
      to = params[1].toLowerCase().replace(/^@/, '')
      points = Math.min(params[2].length - 1, 3) * (if params[2][0] is '+' then 1 else -1)
      reason = if params[4] isnt undefined then params[4] else null

      r.table('karma').insert({
        from: from
        to: to
        reason: reason
        points: points
      }).run rdbConn, (err, result) ->
        if err
          slack.send {
            text: "Error: #{err}"
            channel: "##{req.body.channel_name}"
            username: 'WGACA'
          }
        else
          r.table('karma').filter(r.row('to').eq(to)).sum('points').run rdbConn, (err, pointsResult) ->
            if err
              slack.send {
                text: "Error: #{err}"
                channel: "##{req.body.channel_name}"
                username: 'WGACA'
              }
            else
              pointsText = (if points > 0 then '+' else '-') + Math.abs(points)
              if reason
                pointsText += " for #{reason}"
              text = "#{to} == #{pointsResult} (#{pointsText})"
              slack.send {
                text: text
                channel: "##{req.body.channel_name}"
                username: 'WGACA'
              }
    if req.body.text.toLowerCase() is 'karma highscores'
      r.table('karma').group('to').sum('points').ungroup().filter(r.row('reduction').ne(0)).orderBy(r.desc('reduction')).limit(10).run rdbConn, (err, highscores) ->
        if err
          slack.send {
            text: "Error: #{err}"
            channel: "##{req.body.channel_name}"
            username: 'WGACA'
          }
        else
          highscoresText = 'Top 10\n'
          for highscore in highscores
            highscoresText += "#{highscore.group} == #{highscore.reduction}\n"

          slack.send {
            text: highscoresText
            channel: "##{req.body.channel_name}"
            username: 'WGACA'
          }
    res.status 200
    res.end()

  app.use router

  app.listen config.express.port, config.express.host, ->
    console.log "Express listening on #{config.express.host}:#{config.express.port}"
