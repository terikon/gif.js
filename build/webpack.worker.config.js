const config = require('./webpack.base.config');
const merge = require('webpack-merge');

module.exports = merge(config, {
  entry: {
    'gif.worker': './src/gif.worker.coffee',
  },
  output: {
    path: 'dist',
    filename: '[name].js',
  },
});