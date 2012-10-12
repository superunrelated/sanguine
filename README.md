# Sanguine

An image build system for creating optimized png's, jpg's for normal and retina screens. 

## Installation

Install imagemagick
```bash
$ brew install imagemagick
```

Install pngquant
```url
http://www.libpng.org/pub/png/apps/pngquant.html
```

Then
```bash
$ npm -g install sanguine
```

## Use

```bash
$ sanguine path/to/my/project
```

### Configuration

Add a sanguine.json file to your project:

```json
[
  {
    "source" : "images/card",
    "target" : "www/assets/images/card",
    "colors" : [64],
    "jpg" : [60],
    "embelish" : true
  }
]
```