// GenericResource.h
#if !defined(_GENERICRESOURCE_H)
#define _GENERICRESOURCE_H
#include "Resource.h"

class GenericResource : public Resource {
public:
  /**
   * Constructor
   *
   * @param unit is a string indicating the resource unit 
   * @param quality is a string indicating a quality 
   * @param quantity is a double indicating the quantity
   */
  GenericResource(std::string units, std::string quality, double quantity);

  /**
   * A boolean comparing the quality of the second resource 
   * to the quality of the first 
   *
   * @param first The base resource
   * @param second The resource to evaluate
   *
   * @return True if second is sufficiently equal in quality to 
   * first, False otherwise.
   */
  virtual bool checkQuality(Resource* first, Resource* second);

  /**
   * Returns the total quantity of this resource in its base unit 
   *
   * @return the total quantity of this resource in its base unit
   */
  virtual double getQuantity(){return quantity_;};
    
  /**
   * Returns the total quantity of this resource in its base unit 
   *
   * @return the total quantity of this resource in its base unit
   */
  virtual std::string getResourceUnits(){return units_;};
    
  /**
   * Sets the total quantity of this resource in its base unit 
   */
  virtual void setQuantity(double new_quantity){quantity_ = new_quantity;};

  /**
   * Sets the quality of this resource
   */
  void setQuality(std::string new_quality){quality_ = new_quality;};
    
  /**
   * A boolean comparing the quantity of the second resource is 
   * to the quantity of the first 
   *
   * @param first The base resource
   * @param second The resource to evaluate
   *
   * @return True if second is sufficiently equal in quantity to 
   * first, False otherwise.
   */
  virtual bool checkQuantityEqual(Resource* first, Resource* second);

  /**
   * Returns true if the quantity of the second resource is 
   * greater than the quantity of the first 
   *
   * @param first The base resource
   * @param second The resource to evaluate
   *
   * @return True if second is sufficiently equal in quantity to 
   * first, False otherwise.
   */
  virtual bool checkQuantityGT(Resource* first, Resource* second);

protected:
  /**
   * The quality distinguishing this resource will be traded as.
   */
  std::string units_;

  /**
   * The quality distinguishing this resource will be traded as.
   */
  std::string quality_;

  /**
   * The quality distinguishing this resource will be traded as.
   */
  double quantity_;

};

#endif
