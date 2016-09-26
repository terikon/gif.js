const webpack = require('webpack');

module.exports = {
  module: {
    loaders: [{
      test: /\.coffee$/,
      loader: 'coffee',
    }],
  },
  devtool: 'source-map',
  plugins: [
    new webpack.optimize.UglifyJsPlugin()
  ]
};
