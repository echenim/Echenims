using System;
using System.IO;

namespace Echenim.Nine.Util.Audit
{

    public class TracingLayout : ExceptionLayout
    {
        public override void Format(TextWriter textWriter, LoggingEvent loggingEvent)
        {
            base.Format(textWriter, loggingEvent);

            if (loggingEvent.ExceptionObject != null)
                textWriter.Write(Environment.StackTrace);
        }
    }
}