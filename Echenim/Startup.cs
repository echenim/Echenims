using Microsoft.Owin;
using Owin;

[assembly: OwinStartupAttribute(typeof(Echenim.Startup))]
namespace Echenim
{
    public partial class Startup
    {
        public void Configuration(IAppBuilder app)
        {
            ConfigureAuth(app);
        }
    }
}
