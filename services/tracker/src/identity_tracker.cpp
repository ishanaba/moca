#include "moca/tracking/identity_tracker.hpp"
#include <algorithm>
#include <unordered_set>

namespace { float iou(const std::array<float,4>& a,const std::array<float,4>& b){const float x1=std::max(a[0],b[0]),y1=std::max(a[1],b[1]),x2=std::min(a[2],b[2]),y2=std::min(a[3],b[3]);const float inter=std::max(0.F,x2-x1)*std::max(0.F,y2-y1);const auto area=[](auto& q){return std::max(0.F,q[2]-q[0])*std::max(0.F,q[3]-q[1]);};const float total=area(a)+area(b)-inter;return total>0?inter/total:0;}}
namespace moca {
IdentityTracker::IdentityTracker(std::chrono::milliseconds hold):hold_(hold){}
std::vector<TrackedDetection> IdentityTracker::update(std::vector<Detection> detections,std::chrono::steady_clock::time_point now){
 for(auto it=tracks_.begin();it!=tracks_.end();) if(now-it->second.seen>hold_) it=tracks_.erase(it); else ++it;
 std::sort(detections.begin(),detections.end(),[](auto&a,auto&b){return a.box[0]<b.box[0];});std::unordered_set<std::uint32_t> used;std::vector<TrackedDetection> out;
 for(auto& d:detections){float best=.15F;std::uint32_t id=next_id_;for(auto&[candidate,t]:tracks_)if(!used.contains(candidate)){float score=iou(d.box,t.box);if(score>=best){best=score;id=candidate;}}if(id==next_id_)++next_id_;used.insert(id);tracks_[id]={d.box,now};out.push_back({id,std::move(d)});}return out;
}
}
