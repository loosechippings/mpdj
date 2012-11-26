#!/usr/bin/ruby

require "net/http"
require "uri"
require "rexml/document"
require "socket"
include REXML

KEY="28f974793c22364fd7ecbb9cd77815ba"

ADDRESS="http://ws.audioscrobbler.com/2.0/"

BASE_PARAMS={:api_key=>KEY,:limit=>20,:autocorrect=>1}

def create_track_hash (all_tracks)
	titles={}

	all_tracks.each do |track|
		a=titles[track[:Title]]
		if a == nil then
			a=[]
			titles[track[:Title]]=a
		end
		a.push track	
	end

	return titles
end

def create_artist_hash (all_tracks)
	artists={}

	all_tracks.each do |track|
		a=artists[track[:Artist]]
		if a == nil then
			a=[]
			artists[track[:Artist]]=a
		end
		a.push track	
	end

	return artists
end

def mpd_interface(soc,cmd)
	all_tracks=[]
	track={}

	soc.send cmd+"\n",0
	until (line=soc.gets)=~/^OK*/
		if line=~/^file/ then
			track={}
 			all_tracks<<track
		end
		tag,value=line.split(/:/)
		track[:"#{tag.strip}"]=value.strip
	end

	return all_tracks
end

def call_lfm(extra_params)
	uri=URI(ADDRESS)
	params=BASE_PARAMS.merge extra_params
	
	uri.query=URI.encode_www_form(params)
	puts uri

	Net::HTTP.get(uri)
end

def parse_lfm_tracks(result)
	doc=Document.new(result)

	all_tracks=[]

	XPath.each(doc,"/lfm/similartracks/track[match>0.01]") do |element| 
		title=element.elements["name"].text
		artist=element.elements["artist/name"].text

		all_tracks<<{:Title=>title,:Artist=>artist}
	end

	return all_tracks
end

def parse_lfm_artists(result)
	doc=Document.new(result)

	all_artists=[]

	XPath.each(doc,"/lfm/similarartists/artist[match>0.01]") do |element| 
		artist=element.elements["name"].text

		all_artists<<{:Artist=>artist}
	end

	return all_artists
end

def get_similar_artists(artist)
	params={:method=>"artist.getsimilar",:artist=>artist}
	result=call_lfm(params)
	return parse_lfm_artists(result)
end

def get_similar_tracks(artist,track)
	params={:method=>"track.getsimilar",:artist=>artist,:track=>track}
	result=call_lfm(params)
	return parse_lfm_tracks(result)
end

mpdSocket=TCPSocket.new 'localhost',6600

until line=mpdSocket.gets=~/^OK*/
	puts line
end
puts 'connected'

library=mpd_interface(mpdSocket,"listallinfo")
artists=create_artist_hash library
titles=create_track_hash library

track=mpd_interface(mpdSocket,"currentsong")[0]

puts "Now playing: "+track[:Title]+" by "+track[:Artist]

possible_tracks=[]

tracks=get_similar_tracks(track[:Artist],track[:Title])

if tracks.length>0 then
	tracks.each do |track|
		t=titles[track[:Title]]
		if t != nil then
			t.each {|track_by_artist| possible_tracks.push track_by_artist}
		end
	end
end

get_similar_artists(track[:Artist]).each do |track|
	artist_tracks=artists[track[:Artist]]
	if artist_tracks != nil then
		artists[track[:Artist]].each {|track| possible_tracks.push track}
	end
end


puts possible_tracks
possible_tracks.each {|track| puts track[:Title]+" by "+track[:Artist]}
r=rand(possible_tracks.length)
puts possible_tracks[r][:file]
possible_tracks[r][:LastPlayed]=Time.now

mpd_interface(mpdSocket,"add \""+possible_tracks[r][:file]+"\"")
