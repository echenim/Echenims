using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Echenim.Nine.Util.UniqueReferenceGenerator.Processs;

namespace Echenim.Run
{
    class Program
    {
        static void Main(string[] args)
        {
            var reference = new ReferenceGenerator();

            for(var i = 0; i<10000; ++i)
            {
                Console.WriteLine(reference.GenerateId("S0002"));
            }
           
            Console.ReadLine();
        }
    }
}
