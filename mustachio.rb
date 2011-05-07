require 'sinatra/base'
require 'magickly'
require 'image_size'

# thanks to http://therantsandraves.com/?p=602 for the 'staches
MUSTACHE_FILENAME = File.expand_path(File.join('public', 'images', 'mustache_03.png'))
MUSTACHE_WIDTH, MUSTACHE_HEIGHT = ImageSize.new(File.new(MUSTACHE_FILENAME)).get_size

FACE_POS_ATTRS = ['center', 'eye_left', 'eye_right', 'mouth_left', 'mouth_center', 'mouth_right', 'nose']

Magickly.dragonfly.configure do |c|
  c.analyser.add :face_data do |temp_object|
    Mustachio.face_client.faces_detect(:file => temp_object.file, :attributes => 'none')['photos'].first
  end
  
  c.analyser.add :face_data_as_px do |temp_object|
    data = Mustachio.face_client.faces_detect(:file => temp_object.file, :attributes => 'none')['photos'].first # TODO use #face_data
    FACE_POS_ATTRS.each do |pos_attr|
      data['tags'].map! do |face|
        face[pos_attr]['x'] *= (data['width'] / 100.0)
        face[pos_attr]['y'] *= (data['height'] / 100.0)
        face
      end
    end
    
    data
  end
  
  c.job :mustachify do
    photo_data = @job.face_data_as_px
    width = photo_data['width']
    
    commands = []
    photo_data['tags'].each do |face|
      # perform affine transform, such that the top-center
      # of the mustache is mapped to the nose, and the bottom-center
      # of the stache is mapped to the center of the mouth
      affine_params = [
        [MUSTACHE_WIDTH/2, 0], # top-center of stache
        [face['nose']['x'], face['nose']['y']], # nose
        
        [MUSTACHE_WIDTH/2, MUSTACHE_HEIGHT], # bottom-center of stache
        [face['mouth_center']['x'], face['mouth_center']['y']] # center of mouth
      ]
      affine_params_str = affine_params.map{|p| p.join(',') }.join(' ')
      
      commands << "\\( #{MUSTACHE_FILENAME} +distort Affine '#{affine_params_str}' \\)"
    end
    commands << "-flatten"
    
    command_str = commands.join(' ')
    process :convert, command_str
  end
end

class Mustachio < Sinatra::Base
  @@face_client = Face.get_client(
    :api_key => (ENV['MUSTACHIO_FACE_API_KEY'] || raise("Please set MUSTACHIO_FACE_API_KEY.")),
    :api_secret => (ENV['MUSTACHIO_FACE_API_SECRET'] || raise("Please set MUSTACHIO_FACE_API_SECRET."))
  )
  
  set :static, true
  set :public, 'public'
  
  configure :production do
    require 'newrelic_rpm' if ENV['NEW_RELIC_ID']
  end
  
  class << self
    def face_client
      @@face_client
    end
  end
  
  get '/' do
    src = params[:src]
    if src
      image = Magickly.process_src params[:src], :mustachify => true
      image.to_response(env)
    else
      <<-END
      <html>
      <head></head>
      <body>
      <img src="http://mustachio.heroku.com/magickly/?mustachify=true&src=http://www.librarising.com/astrology/celebs/images2/QR/queenelizabethii.jpg"/>
      <h1>http://#{env['HTTP_HOST']}/?src=<em>YOUR_IMAGE_URL</em></h1>
      </body>
      </html>
      END
    end
  end
end
