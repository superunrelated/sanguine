var CONFIG, easyimg, exec, fs, im, log, path, sanguine, trace, util, _,
  __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };

fs = require('fs');

path = require('path');

util = require('util');

_ = require('underscore');

exec = require('child_process').exec;

easyimg = require('easyimage');

im = require('node-imagemagick');

log = console.log, trace = console.trace;

CONFIG = '/sanguine.json';

module.exports = sanguine = (function() {

  function sanguine() {
    this._deleteFile = __bind(this._deleteFile, this);

    this._duplicateFile = __bind(this._duplicateFile, this);

    this._createFilename = __bind(this._createFilename, this);

    this._optimizeFile = __bind(this._optimizeFile, this);

    this._jpgFile = __bind(this._jpgFile, this);

    this._unretinaFile = __bind(this._unretinaFile, this);

    this._getAllRegExp = __bind(this._getAllRegExp, this);

    this._cleanup = __bind(this._cleanup, this);

    this._fileParsed = __bind(this._fileParsed, this);

    this._parseFile = __bind(this._parseFile, this);

    this._generate = __bind(this._generate, this);

    this._parseDirectory = __bind(this._parseDirectory, this);

    this._parseConfig = __bind(this._parseConfig, this);
    this.base = null;
    this.images = [];
    this.filecount = 0;
    this.existCount = 0;
    this.cleanup = [];
    this.colorRegexp = /-(\d+)c/g;
    this.jpgRegexp = /-(\d+)j/g;
    this.retinaTagRegexp = /(-1x)|(-2x)/g;
    this.retinaRegexp = /-2x/g;
  }

  sanguine.prototype.optimize = function(configpath) {
    var _this = this;
    this.configpath = configpath;
    if (!this.configpath) {
      this.configpath = './';
    }
    if (this.configpath.indexOf(CONFIG) === -1) {
      this.configpath = path.join(this.configpath + CONFIG);
    }
    this.configpath = path.normalize(this.configpath);
    this.base = path.dirname(this.configpath);
    log("@configpath", this.configpath);
    return this._loadJSON(this.configpath, function(err, config) {
      if (err) {
        return log(err);
      }
      return _this._parseConfig(config);
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
    var _this = this;
    return fs.readdir(source, function(err, files) {
      _.each(files, function(file, key) {
        var src, stats;
        src = path.join(source, file);
        stats = fs.statSync(src);
        if (err) {
          log(err);
        }
        if (stats.isDirectory()) {
          return _this._parseDirectory(src, path.join(target, file), set);
        } else if (stats.isFile() && path.extname(src) === '.png') {
          return _this.images.push({
            src: src,
            target: target,
            set: set
          });
        }
      });
      return _this._generate();
    });
  };

  sanguine.prototype._generate = function() {
    var _this = this;
    _.each(this.images, function(image) {
      return _this._parseFile(image.src, image.target, image.set);
    });
    return log(this.existCount, 'files in set allready existed and was ignored.');
  };

  sanguine.prototype._parseFile = function(src, target, set) {
    var fileColors, fileJpg, fileTarget, unretinaTarget,
      _this = this;
    if (!fs.existsSync(target)) {
      fs.mkdirSync(target);
    }
    this.retinaRegexp.lastIndex = 0;
    if (this.retinaRegexp.test(src)) {
      unretinaTarget = src.replace(this.retinaRegexp, '-1x');
      this._unretinaFile(src, unretinaTarget, function(err) {
        if (err) {
          return;
        }
        _this.cleanup.push(unretinaTarget);
        return _this._parseFile(unretinaTarget, target, set);
      });
    }
    fileTarget = path.join(target, path.basename(src));
    fileTarget = fileTarget.replace(this.colorRegexp, '');
    fileTarget = fileTarget.replace(this.jpgRegexp, '');
    fileColors = this._getAllRegExp(this.colorRegexp, src);
    fileJpg = this._getAllRegExp(this.jpgRegexp, src);
    if (fileColors.length === 0 && fileJpg.length === 0) {
      fileColors = set.colors;
      fileJpg = set.jpg;
    }
    if (fileColors.length > 0) {
      _.each(fileColors, function(color) {
        return _this._optimizeFile(src, fileTarget, color, fileColors.length > 1 || set.embelish, _this._fileParsed);
      });
    }
    if (fileJpg.length > 0) {
      return _.each(fileJpg, function(quality) {
        return _this._jpgFile(src, fileTarget, quality, fileJpg.length > 1 || set.embelish, _this._fileParsed);
      });
    }
  };

  sanguine.prototype._fileParsed = function(err, src, target) {
    if (err) {
      return;
    }
    return log('Created: ' + target);
  };

  sanguine.prototype._cleanup = function() {
    var _this = this;
    if (this.cleanup.length > 0) {
      return _.each(this.cleanup, function(file) {
        return _this._deleteFile(file);
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

  sanguine.prototype._unretinaFile = function(src, target, fn) {
    var _this = this;
    return im.identify(src, function(err, imageData) {
      var th, tw;
      if (err) {
        throw err;
      }
      tw = parseInt(imageData.width * 0.5);
      th = parseInt(imageData.height * 0.5);
      log('Shot at ', src, imageData.width, imageData.height);
      return im.convert([src, '-resize', tw + 'x' + th, target], function(err, stdout) {
        if (err) {
          throw err;
        }
        return fn(null, src, stdout);
      });
    });
  };

  sanguine.prototype._jpgFile = function(src, target, quality, embelish, fn) {
    var _this = this;
    if (embelish) {
      target = this._createFilename(target, '-' + quality + 'j');
    }
    target = target.replace('.png', '.jpg');
    if (fs.existsSync(target)) {
      this.existCount++;
      return fn(new Error('File exists:', target));
    }
    im.convert([src, '-quality', quality, target], function(err, stdout) {
      if (err) {
        return fn(err);
      }
      return fn(null, src, stdout);
    });
    return easyimg.convert({
      src: src,
      dst: target,
      quality: quality
    }, function(err, stdout, stderr) {
      if (err) {
        return fn(err);
      }
      return fn(null, src, target);
    });
  };

  sanguine.prototype._optimizeFile = function(src, target, colors, embelish, fn) {
    var _this = this;
    if (embelish) {
      target = this._createFilename(target, '-' + colors + 'c');
    }
    if (fs.existsSync(target)) {
      this.existCount++;
      return fn(new Error('File exists:', target));
    }
    return this._duplicateFile(src, target, function(err) {
      var child;
      if (err) {
        return fn(err);
      }
      return child = exec('pngquant -ext .png -force -speed 1 -verbose ' + colors + ' ' + target, function(err, stdout, stderr) {
        if (err != null) {
          fn(err);
        }
        return fn(null, src, target);
      });
    });
  };

  sanguine.prototype._createFilename = function(target, tag) {
    var match, type;
    this.retinaTagRegexp.lastIndex = 0;
    match = this.retinaTagRegexp.exec(target);
    if (match != null) {
      type = match[0];
      target = target.replace(type, tag + type);
    } else {
      target = target.replace('.', tag + '.');
    }
    return target;
  };

  sanguine.prototype._duplicateFile = function(src, target, fn) {
    var rs, ws,
      _this = this;
    this._deleteFile(target);
    rs = fs.createReadStream(src);
    ws = fs.createWriteStream(target);
    if (rs && ws) {
      rs.pipe(ws);
      rs.once('error', function(err) {
        return fn(err);
      });
      return rs.once('end', function(err) {
        if (err) {
          fn(err);
        }
        rs.destroy();
        ws.destroy();
        return fn();
      });
    }
  };

  sanguine.prototype._deleteFile = function(target) {
    if (fs.existsSync(target)) {
      return fs.unlinkSync(target);
    }
  };

  return sanguine;

})();
