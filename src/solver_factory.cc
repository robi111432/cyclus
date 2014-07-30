#include "solver_factory.h"

#include <iostream>

#include "OsiClpSolverInterface.hpp"
#include "OsiCbcSolverInterface.hpp"

#include "CbcSolver.hpp"

#include "error.h"

namespace cyclus {

// 10800 s = 3 hrs * 60 min/hr * 60 s/min
SolverFactory::SolverFactory() : t_("cbc"), tmax_(10800) { }
SolverFactory::SolverFactory(std::string t) : t_(t), tmax_(10800) { }
SolverFactory::SolverFactory(std::string t, double tmax)
    : t_(t),
      tmax_(tmax) { }

OsiSolverInterface* SolverFactory::get() {
  if (t_ == "clp" || t_ == "cbc") {
    OsiClpSolverInterface* s = new OsiClpSolverInterface();
    s->getModelPtr()->setMaximumSeconds(tmax_);
    return s;
  } else {
    throw ValueError("invalid SolverFactory type '" + t_ + "'");
  }
}

void ReportProg(OsiSolverInterface* si) {
  const double* objs = si->getObjCoefficients();
  const double* clbs = si->getColLower();
  const double* cubs = si->getColUpper();
  int ncol = si->getNumCols();
  std::cout << "Column info\n";
  for (int i = 0; i != ncol; i ++) {
    std::cout << i
              << " obj" << ": " << objs[i]
              << " lb" << ": " << clbs[i]
              << " ub" << ": " << cubs[i]
              << " int" << ": " << std::boolalpha << si->isInteger(i) << '\n';
  }

  const CoinPackedMatrix* m = si->getMatrixByRow();
  const double* rlbs = si->getRowLower();
  const double* rubs = si->getRowUpper();
  int nrow = si->getNumRows();
  std::cout << "Row info\n";
  for (int i = 0; i != nrow; i ++) {
    std::cout << i
              << " lb" << ": " << rlbs[i]
              << " ub" << ": " << rubs[i] << '\n';
  }
  std::cout << "matrix:\n";
  m->dumpMatrix();
}

static int callBack(CbcModel * model, int whereFrom)
{
  int returnCode=0;
  switch (whereFrom) {
  case 1:
  case 2:
    if (!model->status()&&model->secondaryStatus())
      returnCode=1;
    break;
  case 3:
    {
      //CbcCompareUser compare;
      //model->setNodeComparison(compare);
    }
    break;
  case 4:
    // If not good enough could skip postprocessing
    break;
  case 5:
    break;
  default:
    abort();
  }
  return returnCode;
}

void SolveProg(OsiSolverInterface* si, bool verbose) {
  if (verbose)
    ReportProg(si);

  if (HasInt(si)) {
    const char *argv[] = {"exchng","-solve","-quit"};
    int argc = 3;
    CbcModel model(*si);
    CbcMain0(model);
    CbcMain1(argc, argv, model, callBack);
    si->setColSolution(model.getColSolution());
  } else {
    // no ints, just solve 'initial lp relaxation' 
    si->initialSolve();
  }
  
  if (verbose) {
    const double* soln = si->getColSolution();
    for (int i = 0; i != si->getNumCols(); i ++) {
      std::cout << "soln " << i << ": " << soln[i] << '\n';
    }
  }
}

bool HasInt(OsiSolverInterface* si) {
  int i = 0;
  for (i = 0; i != si->getNumCols(); i++) {
    if (si->isInteger(i)) {
      return true;
    }
  }
  return false;
}

}  // namespace cyclus
