import org.htmlparser.beans.HTMLLinkBean;
import java.net.URL;
import java.net.URLConnection;

public class TestLinks
{
    public static void main(String[] args) 
    {
	try{
        if (args.length<1 || !args[0].startsWith("http://"))
        {
            System.out.println("Usage: java TestPrint http://domain.com");
            System.exit(0);
        }
        URL url = new URL(args[0]);
        URLConnection uc = url.openConnection();
        
        HTMLLinkBean hlb = new HTMLLinkBean();
        System.out.println("The following is base-http connection: ");
        hlb.setConnection(uc);
        System.out.println(hlb.getURL());
        URL [] u = hlb.getLinks();
        System.out.println("The following are links in the page");
        for (int i = 0; i<u.length ;i++ )
        {
            System.out.println(u[i].toString());
        }
	}
	catch(Exception ex)
	{
		System.err.println(ex.toString());
	}
    }
}