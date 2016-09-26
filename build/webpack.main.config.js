const config = require('./webpack.base.config');
const merge = require('webpack-merge');

module.exports = merge(config, {
  entry: {
    gif: './src/gif.coffee',
  },
  output: {
    path: 'dist',
    filename: '[name].js',
    library: 'GIF',
    libraryTarget: 'umd',
  },
});
