{clazz} = require 'cardamom'
assert = require 'assert'

tabSize = 2
tabCache = (Array(x+1).join(' ') for x in [0..tabSize])

Editor = @Editor = clazz 'Editor', ->
  init: ({@el, @mirror, @callback}) ->
    assert.ok @el? or @mirror?, "Editor wants an @el or a premade @mirror"
    @mirror ?= @makeMirror(@el)

  makeMirror: (target) ->
    assert.ok target.length is 1, "Editor target el not unique"
    # Setup CodeMirror instance.
    mirror = CodeMirror target[0],
      value:        '# Just enter CoffeeScript here and press ctrl-Enter (or cmd-Enter) to run it.'
      mode:         'coffeescript'
      theme:        'joeson'
      keyMap:       'sembly'
      autofocus:    yes
      gutter:       yes
      fixedGutter:  yes
      lineNumbers:  yes
      tabSize:      tabSize
    # Sanitization.
    mirror.sanitize = =>
      cursor = mirror.getCursor()
      tabReplaced = @replaceTabs orig=mirror.getValue()
      mirror.setValue tabReplaced
      mirror.setCursor cursor
      return tabReplaced
    # Gutter
    # mirror.setMarker 0, '● ', 'cm-bracket'
    # Events
    mirror.submit = @onSave
    return mirror

  # Utility method to replace all tabs with spaces
  replaceTabs: (str) ->
    accum = []
    lines = str.split '\n'
    for line, i1 in lines
      parts = line.split('\t')
      col = 0
      for part, i2 in parts
        col += part.length
        accum.push part
        if i2 < parts.length-1
          insertWs = tabSize - col%tabSize
          col += insertWs
          accum.push tabCache[insertWs]
      if i1 < lines.length-1
        accum.push '\n'
    return accum.join ''

  onSave$: ->
    console.log "!"
    value = @mirror.sanitize()
    return if value.trim().length is 0
    @callback? value