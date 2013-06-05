var CONFIG, OUTPUT, exec, fs, imagemagick, log, path, prettyjson, sanguine, trace, util, _,
  __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

fs = require('fs');

path = require('path');

util = require('util');

_ = require('underscore');

exec = require('child_process').exec;

imagemagick = require('imagemagick');

prettyjson = require('prettyjson');

log = console.log, trace = console.trace;

CONFIG = '/sanguine.json';

OUTPUT = '/sanguine_report.json';

module.exports = sanguine = (function() {

  function sanguine() {
    this._optimizeFile = __bind(this._optimizeFile, this);

    this._generateFile = __bind(this._generateFile, this);

    this._generateComplete = __bind(this._generateComplete, this);

    this._generateNextFile = __bind(this._generateNextFile, this);

    this._generate = __bind(this._generate, this);

    this._getTargetName = __bind(this._getTargetName, this);

    this._getAllRegExp = __bind(this._getAllRegExp, this);

    this._addFiles = __bind(this._addFiles, this);

    this._parseDirectory = __bind(this._parseDirectory, this);

    this._parseConfig = __bind(this._parseConfig, this);
    this.base = null;
    this.images = [];
    this.filecount = 0;
    this.existCount = 0;
    this.cleanup = [];
    this.colorRegexp = /(?:-|^)(\d+)c/g;
    this.jpgRegexp = /(?:-|^)(\d+)j/g;
    this.retinaTagsRegexp = /(?:-|^)(?:(1x)|(2x))/g;
    this.retinaRegexp = /(?:-|^)2x/g;
  }

  sanguine.prototype.optimize = function(configpath, report, force) {
    var _this = this;
    this.configpath = configpath;
    this.report = report;
    this.force = force;
    this.configpath;
    if (!this.configpath) {
      this.configpath = './';
    }
    if (this.configpath.indexOf(CONFIG) === -1) {
      this.configpath = path.join(this.configpath + CONFIG);
    }
    this.configpath = path.normalize(this.configpath);
    this.base = path.dirname(this.configpath);
    log("@configpath: ", this.configpath);
    return this._loadJSON(this.configpath, function(err, config) {
      if (err) {
        return log(err);
      }
      _this._parseConfig(config);
      return _this._generate();
    });
  };

  sanguine.prototype._loadJSON = function(path, fn) {
    var _this = this;
    return fs.readFile(path, 'utf8', function(err, data) {
      if (err) {
        return fn(new Error('Failed to load sanguine.json.'));
      }
      try {
        data = JSON.parse(data);
      } catch (err) {
        if (err) {
          return fn(new Error('Failed to parse sanguine.json.'));
        }
      }
      return fn(null, data);
    });
  };

  sanguine.prototype._parseConfig = function(config) {
    var _this = this;
    return _.each(config, function(set) {
      var source, target;
      source = path.join(_this.base, set.source);
      target = path.join(_this.base, set.target);
      return _this._parseDirectory(source, target, set);
    });
  };

  sanguine.prototype._parseDirectory = function(source, target, set) {
    var files,
      _this = this;
    files = fs.readdirSync(source);
    return _.each(files, function(file, key) {
      var colors, jpgs, src, srcName, stats;
      src = path.join(source, file);
      stats = fs.statSync(src);
      if (stats.isDirectory()) {
        return _this._parseDirectory(src, path.join(target, file), set);
      } else if (stats.isFile() && path.extname(src) === '.png') {
        srcName = path.basename(src);
        colors = _this._getAllRegExp(_this.colorRegexp, srcName);
        jpgs = _this._getAllRegExp(_this.jpgRegexp, srcName);
        if (colors.length === 0 && jpgs.length === 0) {
          colors = set.colors;
          jpgs = set.jpg;
        }
        _this._addFiles(colors, 'c', src, target, set.appendQuality);
        return _this._addFiles(jpgs, 'j', src, target, set.appendQuality);
      }
    });
  };

  sanguine.prototype._addFiles = function(arr, type, src, target, appendQuality) {
    var _this = this;
    if (arr.length > 0) {
      return _.each(arr, function(quality) {
        var tag, tgt;
        tag = '';
        if (arr.length > 1 || appendQuality) {
          tag = '-' + quality + type;
        }
        tgt = _this._getTargetName(src, target, tag);
        if (type === 'j') {
          tgt = tgt.replace('.png', '.jpg');
        }
        _this.images.push({
          src: src,
          target: tgt,
          scale: '100%',
          quality: quality,
          type: type
        });
        _this.retinaRegexp.lastIndex = 0;
        if (_this.retinaRegexp.test(path.basename(src))) {
          tgt = path.join(path.dirname(tgt), path.basename(tgt).replace('-2x', '-1x'));
          return _this.images.push({
            src: src,
            target: tgt,
            scale: '50%',
            quality: quality,
            type: type
          });
        }
      });
    }
  };

  sanguine.prototype._getAllRegExp = function(re, str) {
    var arr, match;
    re.lastIndex = 0;
    arr = [];
    while ((match = re.exec(str))) {
      arr.push(parseInt(match[1]));
    }
    return arr;
  };

  sanguine.prototype._getTargetName = function(src, target, tag) {
    var match, name, type;
    name = path.basename(src);
    name = name.replace(this.colorRegexp, '');
    name = name.replace(this.jpgRegexp, '');
    if (tag != null) {
      this.retinaTagsRegexp.lastIndex = 0;
      match = this.retinaTagsRegexp.exec(name);
      if (match != null) {
        type = match[0];
        name = name.replace(type, tag + type);
      } else {
        name = name.replace('.', tag + '.');
      }
    }
    return path.join(target, name);
  };

  sanguine.prototype._generate = function() {
    this.index = -1;
    return this._generateNextFile();
  };

  sanguine.prototype._generateNextFile = function(err) {
    if (err) {
      return log(err);
    }
    this.index++;
    if (this.index < this.images.length) {
      return this._generateFile(this.images[this.index], this._generateNextFile);
    } else {
      return this._generateComplete();
    }
  };

  sanguine.prototype._generateComplete = function() {
    var reportPath;
    if (this.report) {
      reportPath = path.join(this.base, OUTPUT);
      if (fs.existsSync(reportPath)) {
        fs.unlinkSync(reportPath);
      }
      fs.writeFileSync(reportPath, JSON.stringify(this.images, null, 4));
      log(prettyjson.render(this.images));
      console.log('Output saved to ' + reportPath + '.');
    }
    return log('All images created');
  };

  sanguine.prototype._generateFile = function(image, fn) {
    var targetDir,
      _this = this;
    if (fs.existsSync(image.target)) {
      if (!this.force) {
        image.status = 'Existed. Did not create new file.';
        return fn(null);
      }
      fs.unlinkSync(image.target);
    }
    targetDir = path.dirname(image.target);
    if (!fs.existsSync(targetDir)) {
      fs.mkdirSync(targetDir);
    }
    return imagemagick.convert([image.src, '-resize', image.scale, image.target], function(err, stdout) {
      if (err) {
        fn(err);
      }
      if (image.type === 'c') {
        return _this._optimizeFile(image, fn);
      } else {
        image.status = 'Created and optimized file. ' + (_this.force ? '[FORCED]' : void 0);
        return fn(null);
      }
    });
  };

  sanguine.prototype._optimizeFile = function(image, fn) {
    var child,
      _this = this;
    return child = exec('pngquant -ext .png -force -speed 1 -verbose ' + image.quality + ' ' + image.target, function(err, stdout, stderr) {
      if (err != null) {
        fn(err);
      }
      image.status = 'Created and optimized file.' + (_this.force ? '[FORCED]' : void 0);
      return fn(null);
    });
  };

  return sanguine;

})();
