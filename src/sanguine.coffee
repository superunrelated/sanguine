#!/usr/bin/env node

fs = require('fs')
path = require('path')
util = require('util')
_ = require('underscore')
exec = require('child_process').exec
imagemagick = require('imagemagick')
prettyjson = require('prettyjson')
{log, trace} = console

CONFIG = '/sanguine.json'
OUTPUT = '/sanguine_report.json'

module.exports = class sanguine
	constructor: () ->
		@base = null
		@images = []
		@filecount = 0
		@existCount = 0
		@cleanup = []

		@colorRegexp = /(?:-|^)(\d+)c/g
		@jpgRegexp = /(?:-|^)(\d+)j/g
		@retinaTagsRegexp = /(?:-|^)(?:(1x)|(2x))/g
		@retinaRegexp = /(?:-|^)2x/g

	optimize: (@configpath, @report, @force) ->
		@configpath
		unless @configpath
			@configpath = './'
		if @configpath.indexOf(CONFIG) is -1
			@configpath = path.join(@configpath + CONFIG)
		@configpath = path.normalize(@configpath)
		@base = path.dirname(@configpath)

		log("@configpath: ", @configpath)

		@_loadJSON(@configpath, (err, config) =>
			if err then return log(err)
			@_parseConfig(config)
			@_generate()
		)

	_loadJSON: (path, fn) ->
		fs.readFile(path, 'utf8', (err, data) =>
			if err then return fn(new Error('Failed to load sanguine.json.'))
			try
				data = JSON.parse(data)
			catch err
				if err then return fn(new Error('Failed to parse sanguine.json.'))
			fn(null, data)
		)

	_parseConfig: (config) =>
		_.each(config, (set)=>
			source = path.join(@base, set.source)
			target = path.join(@base, set.target)
			@_parseDirectory(source, target, set)
		)

	_parseDirectory: (source, target, set) =>
		files = fs.readdirSync(source)
		_.each(files, (file, key) =>
			src = path.join(source, file)
			stats = fs.statSync(src)
			if stats.isDirectory()
				@_parseDirectory(src, path.join(target, file), set)
			else if stats.isFile() and path.extname(src) is '.png'
				srcName = path.basename(src)
				colors = @_getAllRegExp(@colorRegexp, srcName)
				jpgs = @_getAllRegExp(@jpgRegexp, srcName)
				if colors.length is 0 and jpgs.length is 0
					colors = set.colors
					jpgs = set.jpg
				@_addFiles(colors, 'c', src, target, set.appendQuality)
				@_addFiles(jpgs, 'j', src, target, set.appendQuality)
		)

	_addFiles: (arr, type, src, target, appendQuality) =>
		if arr.length > 0
			_.each(arr, (quality) =>
				tag = ''
				if arr.length > 1 || appendQuality
					tag = '-' + quality + type
				tgt = @_getTargetName(src, target, tag)
				if type is 'j'
					tgt = tgt.replace('.png', '.jpg')
				@images.push(
					src: src
					target: tgt
					scale: '100%'
					quality: quality
					type: type
				)
				# unretina:
				@retinaRegexp.lastIndex = 0
				if @retinaRegexp.test(path.basename(src))
					tgt = path.join(path.dirname(tgt), path.basename(tgt).replace(@retinaTagsRegexp, '$11x'))
					@images.push(
						src: src
						target: tgt
						scale: '50%'
						quality: quality
						type: type
					)
			)

	_getAllRegExp: (re, str) =>
		re.lastIndex = 0
		arr = []
		while (match = re.exec(str))
			arr.push(parseInt(match[1]))
		arr

	_getTargetName: (src, target, tag) =>
		name = path.basename(src)
		name = name.replace(@colorRegexp, '')
		name = name.replace(@jpgRegexp, '')

		if tag?
			@retinaTagsRegexp.lastIndex = 0
			match = @retinaTagsRegexp.exec(name)
			if match?
				type = match[0]
				name = name.replace(type, tag + type)
			else
				name = name.replace('.', tag + '.')

		path.join(target, name)

	# GENERATION:

	_generate: () =>
		@index = -1
		@_generateNextFile()

	_generateNextFile: (err) =>
		if err then return log(err)

		@index++
		if @index < @images.length
			@_generateFile(@images[@index], @_generateNextFile)
		else
			@_generateComplete()

	_generateComplete: () =>
		if @report
			reportPath = path.join(@base, OUTPUT)
			if fs.existsSync(reportPath)
				fs.unlinkSync(reportPath)
			fs.writeFileSync(reportPath, JSON.stringify(@images, null, 4))
			log(prettyjson.render(@images))
			console.log('Output saved to ' + reportPath + '.')

		log('All images created')

	_generateFile: (image, fn) =>
		if fs.existsSync(image.target)
			unless @force
				image.status = 'Existed. Did not create new file.' 
				return fn(null)
			fs.unlinkSync(image.target)

		targetDir = path.dirname(image.target)
		unless fs.existsSync(targetDir)
			fs.mkdirSync(targetDir)

		imagemagick.convert([image.src, '-resize', image.scale, image.target], (err, stdout) =>
			if err then fn(err)
			if image.type is 'c'
				@_optimizeFile(image, fn)
			else
				image.status = 'Created and optimized file. ' + ('[FORCED]' if @force)
				fn(null)
		)

	_optimizeFile: (image, fn) =>
		child = exec('pngquant -ext .png -force -speed 1 -verbose ' + image.quality + ' ' + image.target, (err, stdout, stderr) =>
			if err? then fn(err)
			image.status = 'Created and optimized file.' + ('[FORCED]' if @force)
			fn(null)
		)


