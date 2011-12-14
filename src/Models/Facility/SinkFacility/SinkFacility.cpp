// SinkFacility.cpp
// Implements the SinkFacility class
#include <iostream>
#include "Logger.h"

#include "SinkFacility.h"

#include "GenericResource.h"
#include "Logician.h"
#include "CycException.h"
#include "InputXML.h"
#include "MarketModel.h"

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -    
SinkFacility::SinkFacility(){
}

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -    
SinkFacility::~SinkFacility(){
  // Delete all the Material in the inventory.
  while (!inventory_.empty()) {
    Material* m = inventory_.front();
    inventory_.pop_front();
    delete m;
  }
}

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -    
void SinkFacility::init(xmlNodePtr cur)
{
  FacilityModel::init(cur);

  /// Sink facilities can have many input/output commodities
  /// move XML pointer to current model
  cur = XMLinput->get_xpath_element(cur,"model/SinkFacility");

  /// all facilities require commodities - possibly many
  std::string commod;
  xmlNodeSetPtr nodes = XMLinput->get_xpath_elements(cur,"incommodity");
  for (int i=0;i<nodes->nodeNr;i++) {
    commod = (const char*)(nodes->nodeTab[i]->children->content);
    in_commods_.push_back(commod);
  }

  // get monthly capacity
  capacity_ = strtod(XMLinput->get_xpath_content(cur,"capacity"), NULL);

  // get inventory_size_
  inventory_size_ = strtod(XMLinput->get_xpath_content(cur,"inventorysize"), NULL);

  // get commodity price
  commod_price_ = strtod(XMLinput->get_xpath_content(cur,"commodprice"), NULL);
}

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -    
void SinkFacility::copy(SinkFacility* src)
{
  FacilityModel::copy(src);

  in_commods_ = src->in_commods_;
  capacity_ = src->capacity_;
  inventory_size_ = src->inventory_size_;
  commod_price_ = src->commod_price_;
}

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -    
void SinkFacility::copyFreshModel(Model* src)
{
  copy(dynamic_cast<SinkFacility*>(src));
}

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -    
void SinkFacility::print() 
{ 
  FacilityModel::print();

  std::string msg = "";

  msg += "accepts commodities ";

  for (vector<std::string>::iterator commod=in_commods_.begin();
       commod != in_commods_.end();
       commod++)
  {
    msg += (commod == in_commods_.begin() ? "{" : ", " );
    msg += (*commod);
  }
  msg += "} until its inventory is full at ";
  LOG(LEV_DEBUG2) << msg << inventory_size_ << " units.";
};

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -    
void SinkFacility::handleTick(int time){
  // The sink facility should ask for as much stuff as it can reasonably receive.
  Mass requestAmt;
  // And it can accept amounts no matter how small
  Mass minAmt = 0;
  // check how full its inventory is
  Mass fullness = this->checkInventory();
  // subtract from max size to get total empty space
  Mass emptiness = inventory_size_ - fullness;

  if (emptiness == 0){
    // don't request anything
  }
  else if (emptiness < capacity_){
  // if empty space is less than monthly acceptance capacity, request it,
    // for each commodity, request emptiness/(no commodities)
    for (vector<std::string>::iterator commod = in_commods_.begin();
       commod != in_commods_.end();
       commod++) {
      MarketModel* market = MarketModel::marketForCommod(*commod);
      Communicator* recipient = dynamic_cast<Communicator*>(market);
      // recall that requests have a negative amount
      requestAmt = (emptiness/in_commods_.size());

      // create a generic resource
      GenericResource* request_res = new GenericResource((*commod), "kg", requestAmt);

      // build the transaction and message
      Transaction trans;
      trans.commod = *commod;
      trans.minfrac = minAmt/requestAmt;
      trans.is_offer = false;
      trans.price = commod_price_;
      trans.resource = request_res;

      Message* request = new Message(this, recipient, trans); 
      request->setNextDest(getFacInst());
      request->sendOn();

      LOG(LEV_DEBUG2) << "During handleTick, " << getFacName() << " requests: "<< requestAmt << ".";
    }
  }
  // otherwise, the upper bound is the monthly acceptance capacity, request cap.
  else if (emptiness >= capacity_){
    // for each commodity, request capacity/(noCommodities)
    for (vector<std::string>::iterator commod = in_commods_.begin();
       commod != in_commods_.end();
       commod++) {
      MarketModel* market = MarketModel::marketForCommod(*commod);
      Communicator* recipient = dynamic_cast<Communicator*>(market);
      requestAmt = capacity_/in_commods_.size();

      // build a material
      Material* request_mat = new Material(CompMap(), "", "", requestAmt, MASSBASED, true);

      // build the transaction and message
      Transaction trans;
      trans.commod = *commod;
      trans.minfrac = minAmt/requestAmt;
      trans.is_offer = false;
      trans.price = commod_price_;
      trans.resource = request_mat;

      Message* request = new Message(this, recipient, trans); 
      request->setNextDest(getFacInst());
      request->sendOn();

      LOG(LEV_DEBUG2) << "During handleTick, " << getFacName() << " requests: " << requestAmt << ".";
    }
  }

}

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -    
void SinkFacility::handleTock(int time){

  // On the tock, the sink facility doesn't really do much. 
  // Maybe someday it will record things.
  // For now, lets just print out what we have at each timestep.
  LOG(LEV_DEBUG2) << "SinkFacility " << this->ID()
                  << " is holding " << this->checkInventory()
                  << " units of material at the close of month " << time
                  << ".";
}

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -    
void SinkFacility::receiveMaterial(Transaction trans, vector<Material*> manifest){

  // grab each material object off of the manifest
  // and move it into the inventory.
  for (vector<Material*>::iterator thisMat=manifest.begin();
       thisMat != manifest.end();
       thisMat++)
  {
    LOG(LEV_DEBUG2) <<"SinkFacility " << ID() << " is receiving material with mass "
        << (*thisMat)->getTotMass();
    (*thisMat)->print();
    inventory_.push_back(*thisMat);
  }
}

//- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -    
Mass SinkFacility::checkInventory(){
  Mass total = 0;

  // Iterate through the inventory and sum the amount of whatever
  // material unit is in each object.

  deque<Material*>::iterator iter;

  for (iter = inventory_.begin(); iter != inventory_.end(); iter ++)
    total += (*iter)->getTotMass();

  return total;
}

/* --------------------
 * all MODEL classes have these members
 * --------------------
 */

extern "C" Model* construct() {
  return new SinkFacility();
}

extern "C" void destruct(Model* p) {
  delete p;
}

/* ------------------- */ 

