{EventEmitter} = require 'events'
browser = require './browser.coffee'

class GIF extends EventEmitter

  defaults =
    workerScript: 'gif.worker.js'
    workers: 2
    repeat: 0 # repeat forever, -1 = repeat once
    background: '#fff'
    quality: 10 # pixel sample interval, lower is better
    width: null # size derermined from first frame if possible
    height: null
    transparent: null
    debug: false

  frameDefaults =
    delay: 500 # ms
    copy: false

  constructor: (options) ->
    @running = false

    @options = {}
    @frames = []

    # TODO: compare by instance and not by data
    @groups = new Map() # for [data1, data1, data2, data1] @groups[data1] == [1, 3] and @groups[data2] = [2]

    @freeWorkers = []
    @activeWorkers = []

    @setOptions options
    for key, value of defaults
      @options[key] ?= value

  setOption: (key, value) ->
    @options[key] = value
    if @_canvas? and key in ['width', 'height']
      @_canvas[key] = value

  setOptions: (options) ->
    @setOption key, value for own key, value of options

  addFrame: (image, options={}) ->
    frame = {}
    frame.transparent = @options.transparent
    for key of frameDefaults
      frame[key] = options[key] or frameDefaults[key]

    # use the images width and height for options unless already set
    @setOption 'width', image.width unless @options.width?
    @setOption 'height', image.height unless @options.height?

    if ImageData? and image instanceof ImageData
       frame.data = image.data
    else if (CanvasRenderingContext2D? and image instanceof CanvasRenderingContext2D) or (WebGLRenderingContext? and image instanceof WebGLRenderingContext)
      if options.copy
        frame.data = @getContextData image
      else
        frame.context = image
    else if image.childNodes?
      if options.copy
        frame.data = @getImageData image
      else
        frame.image = image
    else
      throw new Error 'Invalid image'

    # find duplicates in frames.data
    index = @frames.length
    if index > 0 and frame.data # frame 0 contains header, do not count it
      if @groups.has(frame.data)
        @groups.get(frame.data).push index
      else
        @groups.set frame.data, [index]

    @frames.push frame

  render: ->
    throw new Error 'Already running' if @running

    if not @options.width? or not @options.height?
      throw new Error 'Width and height must be set prior to rendering'

    @running = true
    @nextFrame = 0
    @finishedFrames = 0

    @imageParts = (null for i in [0...@frames.length])
    numWorkers = @spawnWorkers()
    # we need to wait for the palette
    if @options.globalPalette == true
      @renderNextFrame()
    else
      @renderNextFrame() for i in [0...numWorkers]

    @emit 'start'
    @emit 'progress', 0

  abort: ->
    loop
      worker = @activeWorkers.shift()
      break unless worker?
      @log "killing active worker"
      worker.terminate()
    @running = false
    @emit 'abort'

  # private

  spawnWorkers: ->
    numWorkers = Math.min(@options.workers, @frames.length)
    [@freeWorkers.length...numWorkers].forEach (i) =>
      @log "spawning worker #{ i }"
      worker = new Worker @options.workerScript
      worker.onmessage = (event) =>
        @activeWorkers.splice @activeWorkers.indexOf(worker), 1
        @freeWorkers.push worker
        @frameFinished event.data, false
      @freeWorkers.push worker
    return numWorkers

  frameFinished: (frame, duplicate) ->
    @finishedFrames++
    if not duplicate
      @log "frame #{ frame.index + 1 } finished - #{ @activeWorkers.length } active"
      @emit 'progress', @finishedFrames / @frames.length
      @imageParts[frame.index] = frame
    else
      indexOfDuplicate = @frames.indexOf frame
      indexOfFirstInGroup = @groups.get(frame.data)[0]
      @log "frame #{ indexOfDuplicate + 1 } is duplicate of #{ indexOfFirstInGroup } - #{ @activeWorkers.length } active"
      @imageParts[indexOfDuplicate] = { indexOfFirstInGroup: indexOfFirstInGroup } # do not put frame here, as it may not be available still. Put index.
    # remember calculated palette, spawn the rest of the workers
    if @options.globalPalette == true and not duplicate
      @options.globalPalette = frame.globalPalette
      @log "global palette analyzed"
      @renderNextFrame() for i in [1...@freeWorkers.length] if @frames.length > 2
    if null in @imageParts
      @renderNextFrame()
    else
      @finishRendering()

  finishRendering: ->
    for frame, index in @imageParts
      @imageParts[index] = @imageParts[frame.indexOfFirstInGroup] if frame.indexOfFirstInGroup
    len = 0
    for frame in @imageParts
      len += (frame.data.length - 1) * frame.pageSize + frame.cursor
    len += frame.pageSize - frame.cursor
    @log "rendering finished - filesize #{ Math.round(len / 1000) }kb"
    data = new Uint8Array len
    offset = 0
    for frame in @imageParts
      for page, i in frame.data
        data.set page, offset
        if i is frame.data.length - 1
          offset += frame.cursor
        else
          offset += frame.pageSize

    image = new Blob [data],
      type: 'image/gif'

    @emit 'finished', image, data

  renderNextFrame: ->
    throw new Error 'No free workers' if @freeWorkers.length is 0
    return if @nextFrame >= @frames.length # no new frame to render

    frame = @frames[@nextFrame++]

    # check if one of duplicates, but not the first in group
    index = @frames.indexOf frame
    if index > 0 and @groups.has(frame.data) and @groups.get(frame.data)[0] != index
      setTimeout =>
        @frameFinished frame, true
      , 0
      return

    worker = @freeWorkers.shift()
    task = @getTask frame

    @log "starting frame #{ task.index + 1 } of #{ @frames.length }"
    @activeWorkers.push worker
    worker.postMessage task#, [task.data.buffer]

  getContextData: (ctx) ->
    return ctx.getImageData(0, 0, @options.width, @options.height).data

  getImageData: (image) ->
    if not @_canvas?
      @_canvas = document.createElement 'canvas'
      @_canvas.width = @options.width
      @_canvas.height = @options.height

    ctx = @_canvas.getContext '2d'
    ctx.setFill = @options.background
    ctx.fillRect 0, 0, @options.width, @options.height
    ctx.drawImage image, 0, 0

    return @getContextData ctx

  getTask: (frame) ->
    index = @frames.indexOf frame
    task =
      index: index
      last: index is (@frames.length - 1)
      delay: frame.delay
      transparent: frame.transparent
      width: @options.width
      height: @options.height
      quality: @options.quality
      dither: @options.dither
      globalPalette: @options.globalPalette
      repeat: @options.repeat
      canTransfer: true

    if frame.data?
      task.data = frame.data
    else if frame.context?
      task.data = @getContextData frame.context
    else if frame.image?
      task.data = @getImageData frame.image
    else
      throw new Error 'Invalid frame'

    return task

  log: (msg) ->
    console.log msg if @options.debug

module.exports = GIF
