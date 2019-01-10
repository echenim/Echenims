using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.AspNet.Identity.EntityFramework;

namespace Echenim.Authentication.Base
{
    // You will not likely need to customize there, but it is necessary/easier to create our own 
    // project-specific implementations, so here they are:

    public class ApplicationUserLogin : IdentityUserLogin<string> { }
}
